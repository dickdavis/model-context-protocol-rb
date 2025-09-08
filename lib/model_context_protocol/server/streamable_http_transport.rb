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
      @require_sessions = transport_options.fetch(:require_sessions, false)
      @default_protocol_version = transport_options.fetch(:default_protocol_version, "2025-03-26")
      @session_protocol_versions = {}  # Track protocol versions per session
      @validate_origin = transport_options.fetch(:validate_origin, true)
      @allowed_origins = transport_options.fetch(:allowed_origins, ["http://localhost", "https://localhost", "http://127.0.0.1", "https://127.0.0.1"])

      @session_store = ModelContextProtocol::Server::SessionStore.new(
        @redis,
        ttl: transport_options[:session_ttl] || 3600
      )

      @server_instance = "#{Socket.gethostname}-#{Process.pid}-#{SecureRandom.hex(4)}"
      @local_streams = {}
      @notification_queue = []
      @sse_event_counter = 0

      setup_redis_subscriber
    end

    def handle
      @configuration.logger.connect_transport(self)

      env = @configuration.transport_options[:env]

      unless env
        raise ArgumentError, "StreamableHTTP transport requires Rack env hash in transport_options"
      end

      case env["REQUEST_METHOD"]
      when "POST"
        handle_post_request(env)
      when "GET"
        handle_sse_request(env)
      when "DELETE"
        handle_delete_request(env)
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

    def validate_headers(env)
      if @validate_origin
        origin = env["HTTP_ORIGIN"]
        if origin && !@allowed_origins.any? { |allowed| origin.start_with?(allowed) }
          error_response = ErrorResponse[id: nil, error: {code: -32600, message: "Origin not allowed"}]
          return {json: error_response.serialized, status: 403}
        end
      end

      accept_header = env["HTTP_ACCEPT"]
      if accept_header
        unless accept_header.include?("application/json") || accept_header.include?("text/event-stream")
          error_response = ErrorResponse[id: nil, error: {code: -32600, message: "Invalid Accept header. Must include application/json or text/event-stream"}]
          return {json: error_response.serialized, status: 400}
        end
      end

      protocol_version = env["HTTP_MCP_PROTOCOL_VERSION"]
      if protocol_version
        # Check if this matches a known negotiated version
        valid_versions = @session_protocol_versions.values.compact.uniq
        unless valid_versions.empty? || valid_versions.include?(protocol_version)
          error_response = ErrorResponse[id: nil, error: {code: -32600, message: "Invalid MCP protocol version: #{protocol_version}. Expected one of: #{valid_versions.join(", ")}"}]
          return {json: error_response.serialized, status: 400}
        end
      end

      nil
    end

    def determine_message_type(body)
      if body.key?("method") && body.key?("id")
        :request
      elsif body.key?("method") && !body.key?("id")
        :notification
      elsif body.key?("id") && body.key?("result") || body.key?("error")
        :response
      else
        :unknown
      end
    end

    def create_initialization_sse_stream_proc(response_data)
      proc do |stream|
        event_id = next_event_id
        send_sse_event(stream, response_data, event_id)
      end
    end

    def create_request_sse_stream_proc(response_data)
      proc do |stream|
        event_id = next_event_id
        send_sse_event(stream, response_data, event_id)
      end
    end

    def next_event_id
      @sse_event_counter += 1
      "#{@server_instance}-#{@sse_event_counter}"
    end

    def send_sse_event(stream, data, event_id = nil)
      if event_id
        stream.write("id: #{event_id}\n")
      end
      message = data.is_a?(String) ? data : data.to_json
      stream.write("data: #{message}\n\n")
      stream.flush if stream.respond_to?(:flush)
    end

    def handle_post_request(env)
      validation_error = validate_headers(env)
      return validation_error if validation_error

      body_string = env["rack.input"].read
      body = JSON.parse(body_string)
      session_id = env["HTTP_MCP_SESSION_ID"]
      accept_header = env["HTTP_ACCEPT"] || ""

      case body["method"]
      when "initialize"
        handle_initialization(body, accept_header)
      else
        handle_regular_request(body, session_id, accept_header)
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

    def handle_initialization(body, accept_header)
      result = @router.route(body)
      response = Response[id: body["id"], result: result.serialized]
      response_headers = {}

      negotiated_protocol_version = result.serialized[:protocolVersion] || result.serialized["protocolVersion"]

      if @require_sessions
        session_id = SecureRandom.uuid
        @session_store.create_session(session_id, {
          server_instance: @server_instance,
          context: @configuration.context || {},
          created_at: Time.now.to_f,
          negotiated_protocol_version: negotiated_protocol_version
        })
        response_headers["Mcp-Session-Id"] = session_id
        @session_protocol_versions[session_id] = negotiated_protocol_version
      else
        @session_protocol_versions[:default] = negotiated_protocol_version
      end

      if accept_header.include?("text/event-stream") && !accept_header.include?("application/json")
        response_headers.merge!({
          "Content-Type" => "text/event-stream",
          "Cache-Control" => "no-cache",
          "Connection" => "keep-alive"
        })

        {
          stream: true,
          headers: response_headers,
          stream_proc: create_initialization_sse_stream_proc(response.serialized)
        }
      else
        response_headers["Content-Type"] = "application/json"
        {
          json: response.serialized,
          status: 200,
          headers: response_headers
        }
      end
    end

    def handle_regular_request(body, session_id, accept_header)
      if @require_sessions
        unless session_id && @session_store.session_exists?(session_id)
          if session_id && !@session_store.session_exists?(session_id)
            error_response = ErrorResponse[id: body["id"], error: {code: -32600, message: "Session terminated"}]
            return {json: error_response.serialized, status: 404}
          else
            error_response = ErrorResponse[id: body["id"], error: {code: -32600, message: "Invalid or missing session ID"}]
            return {json: error_response.serialized, status: 400}
          end
        end
      end

      message_type = determine_message_type(body)

      case message_type
      when :notification, :response
        if session_id && @session_store.session_has_active_stream?(session_id)
          deliver_to_session_stream(session_id, body)
        end
        {json: {}, status: 202}

      when :request
        result = @router.route(body)
        response = Response[id: body["id"], result: result.serialized]

        if session_id && @session_store.session_has_active_stream?(session_id)
          deliver_to_session_stream(session_id, response.serialized)
          return {json: {accepted: true}, status: 200}
        end

        if accept_header.include?("text/event-stream") && !accept_header.include?("application/json")
          {
            stream: true,
            headers: {
              "Content-Type" => "text/event-stream",
              "Cache-Control" => "no-cache",
              "Connection" => "keep-alive"
            },
            stream_proc: create_request_sse_stream_proc(response.serialized)
          }
        else
          {
            json: response.serialized,
            status: 200,
            headers: {"Content-Type" => "application/json"}
          }
        end
      end
    end

    def handle_sse_request(env)
      accept_header = env["HTTP_ACCEPT"] || ""
      unless accept_header.include?("text/event-stream")
        error_response = ErrorResponse[id: nil, error: {code: -32600, message: "Accept header must include text/event-stream"}]
        return {json: error_response.serialized, status: 400}
      end

      session_id = env["HTTP_MCP_SESSION_ID"]
      last_event_id = env["HTTP_LAST_EVENT_ID"]

      if @require_sessions
        unless session_id && @session_store.session_exists?(session_id)
          if session_id && !@session_store.session_exists?(session_id)
            error_response = ErrorResponse[id: nil, error: {code: -32600, message: "Session terminated"}]
            return {json: error_response.serialized, status: 404}
          else
            error_response = ErrorResponse[id: nil, error: {code: -32600, message: "Invalid or missing session ID"}]
            return {json: error_response.serialized, status: 400}
          end
        end
        @session_store.mark_stream_active(session_id, @server_instance)
      end

      {
        stream: true,
        headers: {
          "Content-Type" => "text/event-stream",
          "Cache-Control" => "no-cache",
          "Connection" => "keep-alive"
        },
        stream_proc: create_sse_stream_proc(session_id, last_event_id)
      }
    end

    def handle_delete_request(env)
      session_id = env["HTTP_MCP_SESSION_ID"]

      if session_id
        cleanup_session(session_id)
      end

      {json: {success: true}, status: 200}
    end

    def create_sse_stream_proc(session_id, last_event_id = nil)
      proc do |stream|
        register_local_stream(session_id, stream) if session_id

        if last_event_id
          replay_messages_after_event_id(stream, session_id, last_event_id)
        else
          flush_notifications_to_stream(stream)
        end

        start_keepalive_thread(session_id, stream)

        loop do
          break unless stream_connected?(stream)
          sleep 0.1
        end
      ensure
        cleanup_local_stream(session_id) if session_id
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
      event_id = next_event_id
      send_sse_event(stream, data, event_id)
    end

    def replay_messages_after_event_id(stream, session_id, last_event_id)
      flush_notifications_to_stream(stream)
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
