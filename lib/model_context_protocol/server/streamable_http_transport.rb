require "json"
require "securerandom"

module ModelContextProtocol
  class Server::StreamableHttpTransport
    Response = Data.define(:id, :result) do
      def serialized
        {jsonrpc: "2.0", id:, result:}
      end
    end

    ErrorResponse = Data.define(:id, :error) do
      def serialized
        {jsonrpc: "2.0", id:, error:}
      end
    end
    def initialize(router:, configuration:)
      @router = router
      @configuration = configuration

      transport_options = @configuration.transport_options
      @redis = transport_options[:redis_client]

      @session_store = ModelContextProtocol::Server::SessionStore.new(
        @redis,
        ttl: transport_options[:session_ttl] || 3600
      )

      @server_instance = "#{Socket.gethostname}-#{Process.pid}-#{SecureRandom.hex(4)}"
      @local_streams = {}
      @notification_queue = []

      setup_redis_subscriber
    end

    def handle
      @configuration.logger.connect_transport(self)

      request = @configuration.transport_options[:request]
      response = @configuration.transport_options[:response]

      unless request && response
        raise ArgumentError, "StreamableHTTP transport requires request and response objects in transport_options"
      end

      case request.method
      when "POST"
        handle_post_request(request)
      when "GET"
        handle_sse_request(request, response)
      when "DELETE"
        handle_delete_request(request)
      else
        error_response = ErrorResponse[id: nil, error: {code: -32601, message: "Method not allowed"}]
        {json: error_response.serialized, status: 405}
      end
    end

    def send_notification(method, params)
      notification = {
        jsonrpc: "2.0",
        method: method,
        params: params
      }

      if has_active_streams?
        deliver_to_active_streams(notification)
      else
        @notification_queue << notification
      end
    end

    private

    def handle_post_request(request)
      body_string = request.body.read
      body = JSON.parse(body_string)
      session_id = request.headers["Mcp-Session-Id"]

      case body["method"]
      when "initialize"
        handle_initialization(body)
      else
        handle_regular_request(body, session_id)
      end
    rescue JSON::ParserError
      error_response = ErrorResponse[id: "", error: {code: -32700, message: "Parse error"}]
      {json: error_response.serialized, status: 400}
    rescue ModelContextProtocol::Server::ParameterValidationError => validation_error
      @configuration.logger.error("Validation error", error: validation_error.message)
      error_response = ErrorResponse[id: body&.dig("id"), error: {code: -32602, message: validation_error.message}]
      {json: error_response.serialized, status: 400}
    rescue => e
      @configuration.logger.error("Error handling POST request", error: e.message, backtrace: e.backtrace.first(5))
      error_response = ErrorResponse[id: body&.dig("id"), error: {code: -32603, message: "Internal error"}]
      {json: error_response.serialized, status: 500}
    end

    def handle_initialization(body)
      session_id = SecureRandom.uuid

      @session_store.create_session(session_id, {
        server_instance: @server_instance,
        context: @configuration.context || {},
        created_at: Time.now.to_f
      })

      result = @router.route(body)
      response = Response[id: body["id"], result: result.serialized]

      {
        json: response.serialized,
        status: 200,
        headers: {"Mcp-Session-Id" => session_id}
      }
    end

    def handle_regular_request(body, session_id)
      unless session_id && @session_store.session_exists?(session_id)
        error_response = ErrorResponse[id: body["id"], error: {code: -32600, message: "Invalid or missing session ID"}]
        return {json: error_response.serialized, status: 400}
      end

      result = @router.route(body)
      response = Response[id: body["id"], result: result.serialized]

      if @session_store.session_has_active_stream?(session_id)
        deliver_to_session_stream(session_id, response.serialized)
        {json: {accepted: true}, status: 200}
      else
        {json: response.serialized, status: 200}
      end
    end

    def handle_sse_request(request, response)
      session_id = request.headers["Mcp-Session-Id"]

      unless session_id && @session_store.session_exists?(session_id)
        error_response = ErrorResponse[id: nil, error: {code: -32600, message: "Invalid or missing session ID"}]
        return {json: error_response.serialized, status: 400}
      end

      @session_store.mark_stream_active(session_id, @server_instance)

      {
        stream: true,
        headers: {
          "Content-Type" => "text/event-stream",
          "Cache-Control" => "no-cache",
          "Connection" => "keep-alive"
        },
        stream_proc: create_sse_stream_proc(session_id)
      }
    end

    def handle_delete_request(request)
      session_id = request.headers["Mcp-Session-Id"]

      if session_id
        cleanup_session(session_id)
      end

      {json: {success: true}, status: 200}
    end

    def create_sse_stream_proc(session_id)
      proc do |stream|
        register_local_stream(session_id, stream)

        flush_notifications_to_stream(stream)

        start_keepalive_thread(session_id, stream)

        loop do
          break unless stream_connected?(stream)
          sleep 0.1
        end
      ensure
        cleanup_local_stream(session_id)
      end
    end

    def register_local_stream(session_id, stream)
      @local_streams[session_id] = stream
    end

    def cleanup_local_stream(session_id)
      @local_streams.delete(session_id)
      @session_store.mark_stream_inactive(session_id)
    end

    def stream_connected?(stream)
      return false unless stream

      begin
        stream.write(": ping\n\n")
        stream.flush if stream.respond_to?(:flush)
        true
      rescue IOError, Errno::EPIPE, Errno::ECONNRESET
        false
      end
    end

    def start_keepalive_thread(session_id, stream)
      Thread.new do
        loop do
          sleep 30
          break unless stream_connected?(stream)

          begin
            send_ping_to_stream(stream)
          rescue IOError, Errno::EPIPE, Errno::ECONNRESET
            break
          end
        end
      rescue => e
        @configuration.logger.error("Keepalive thread error", error: e.message)
      ensure
        cleanup_local_stream(session_id)
      end
    end

    def send_ping_to_stream(stream)
      stream.write(": ping #{Time.now.iso8601}\n\n")
      stream.flush if stream.respond_to?(:flush)
    end

    def send_to_stream(stream, data)
      message = data.is_a?(String) ? data : data.to_json
      stream.write("data: #{message}\n\n")
      stream.flush if stream.respond_to?(:flush)
    end

    def deliver_to_session_stream(session_id, data)
      if @local_streams[session_id]
        begin
          send_to_stream(@local_streams[session_id], data)
          return true
        rescue IOError, Errno::EPIPE, Errno::ECONNRESET
          cleanup_local_stream(session_id)
        end
      end

      @session_store.route_message_to_session(session_id, data)
    end

    def cleanup_session(session_id)
      cleanup_local_stream(session_id)
      @session_store.cleanup_session(session_id)
    end

    def setup_redis_subscriber
      Thread.new do
        @session_store.subscribe_to_server(@server_instance) do |data|
          session_id = data["session_id"]
          message = data["message"]

          if @local_streams[session_id]
            begin
              send_to_stream(@local_streams[session_id], message)
            rescue IOError, Errno::EPIPE, Errno::ECONNRESET
              cleanup_local_stream(session_id)
            end
          end
        end
      rescue => e
        @configuration.logger.error("Redis subscriber error", error: e.message, backtrace: e.backtrace.first(5))
        sleep 5
        retry
      end
    end

    def has_active_streams?
      @local_streams.any?
    end

    def deliver_to_active_streams(notification)
      @local_streams.each do |session_id, stream|
        send_to_stream(stream, notification)
      rescue IOError, Errno::EPIPE, Errno::ECONNRESET
        cleanup_local_stream(session_id)
      end
    end

    def flush_notifications_to_stream(stream)
      while (notification = @notification_queue.shift)
        send_to_stream(stream, notification)
      end
    end
  end
end
