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
      @redis_pool = ModelContextProtocol::Server::RedisConfig.pool
      @require_sessions = transport_options.fetch(:require_sessions, false)
      @default_protocol_version = transport_options.fetch(:default_protocol_version, "2025-03-26")
      @session_protocol_versions = {}
      @validate_origin = transport_options.fetch(:validate_origin, true)
      @allowed_origins = transport_options.fetch(:allowed_origins, ["http://localhost", "https://localhost", "http://127.0.0.1", "https://127.0.0.1"])
      @redis = ModelContextProtocol::Server::RedisClientProxy.new(@redis_pool)

      @session_store = SessionStore.new(
        @redis,
        ttl: transport_options[:session_ttl] || 3600
      )

      @server_instance = "#{Socket.gethostname}-#{Process.pid}-#{SecureRandom.hex(4)}"
      @stream_registry = StreamRegistry.new(@redis, @server_instance)
      @notification_queue = NotificationQueue.new(@redis, @server_instance)
      @event_counter = EventCounter.new(@redis, @server_instance)
      @request_store = RequestStore.new(@redis, @server_instance)
      @stream_monitor_thread = nil
      @message_poller = MessagePoller.new(@redis, @stream_registry, @configuration.logger) do |stream, message|
        send_to_stream(stream, message)
      end

      start_message_poller
      start_stream_monitor
    end

    def shutdown
      @configuration.logger.info("Shutting down StreamableHttpTransport")

      # Stop the message poller
      @message_poller&.stop

      # Stop the stream monitor thread
      if @stream_monitor_thread&.alive?
        @stream_monitor_thread.kill
        @stream_monitor_thread.join(timeout: 5)
      end

      # Unregister all local streams
      @stream_registry.get_all_local_streams.each do |session_id, stream|
        @stream_registry.unregister_stream(session_id)
        @session_store.mark_stream_inactive(session_id)
      rescue => e
        @configuration.logger.error("Error during stream cleanup", session_id: session_id, error: e.message)
      end

      @redis_pool.checkin(@redis) if @redis_pool && @redis

      @configuration.logger.info("StreamableHttpTransport shutdown complete")
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

      if @stream_registry.has_any_local_streams?
        deliver_to_active_streams(notification)
      else
        @notification_queue.push(notification)
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

    def create_progressive_request_sse_stream_proc(request_body, session_id)
      proc do |stream|
        temp_stream_id = session_id || "temp-#{SecureRandom.hex(8)}"
        @stream_registry.register_stream(temp_stream_id, stream)

        begin
          result = @router.route(request_body, request_store: @request_store, session_id: session_id, transport: self)

          if result
            response = Response[id: request_body["id"], result: result.serialized]

            event_id = next_event_id
            send_sse_event(stream, response.serialized, event_id)
          else
            event_id = next_event_id
            send_sse_event(stream, {}, event_id)
          end

          # Close stream immediately when work is complete
          close_stream(temp_stream_id, reason: "request_completed")
        rescue IOError, Errno::EPIPE, Errno::ECONNRESET
          # Client disconnected during processing
        ensure
          # Fallback cleanup
          @stream_registry.unregister_stream(temp_stream_id)
        end
      end
    end

    def next_event_id
      @event_counter.next_event_id
    end

    def send_sse_event(stream, data, event_id = nil)
      if event_id
        stream.write("id: #{event_id}\n")
      end
      message = data.is_a?(String) ? data : data.to_json
      stream.write("data: #{message}\n\n")
      stream.flush if stream.respond_to?(:flush)
    end

    def close_stream(session_id, reason: "completed")
      if (stream = @stream_registry.get_local_stream(session_id))
        begin
          send_sse_event(stream, {type: "stream_complete", reason: reason})
          stream.close
        rescue IOError, Errno::EPIPE, Errno::ECONNRESET, Errno::ENOTCONN, Errno::EBADF
          nil
        end

        @stream_registry.unregister_stream(session_id)
        @session_store.mark_stream_inactive(session_id) if @require_sessions
      end
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
      result = @router.route(body, transport: self)
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
        if body["method"] == "notifications/cancelled"
          handle_cancellation(body, session_id)
        elsif session_id && @session_store.session_has_active_stream?(session_id)
          deliver_to_session_stream(session_id, body)
        end
        {json: {}, status: 202}

      when :request
        has_progress_token = body.dig("params", "_meta", "progressToken")
        should_stream = (accept_header.include?("text/event-stream") && !accept_header.include?("application/json")) ||
          has_progress_token

        if should_stream
          {
            stream: true,
            headers: {
              "Content-Type" => "text/event-stream",
              "Cache-Control" => "no-cache",
              "Connection" => "keep-alive"
            },
            stream_proc: create_progressive_request_sse_stream_proc(body, session_id)
          }
        else
          result = @router.route(body, request_store: @request_store, session_id: session_id, transport: self)

          if result
            response = Response[id: body["id"], result: result.serialized]

            if session_id && @session_store.session_has_active_stream?(session_id)
              deliver_to_session_stream(session_id, response.serialized)
              return {json: {accepted: true}, status: 200}
            end

            {
              json: response.serialized,
              status: 200,
              headers: {"Content-Type" => "application/json"}
            }
          else
            {json: {}, status: 204}
          end
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
        @stream_registry.register_stream(session_id, stream) if session_id

        if last_event_id
          replay_messages_after_event_id(stream, session_id, last_event_id)
        else
          flush_notifications_to_stream(stream)
        end

        loop do
          break unless stream_connected?(stream)
          sleep 0.1
        end
      ensure
        @stream_registry.unregister_stream(session_id) if session_id
      end
    end

    def stream_connected?(stream)
      return false unless stream

      begin
        stream.write(": ping\n\n")
        stream.flush if stream.respond_to?(:flush)
        true
      rescue IOError, Errno::EPIPE, Errno::ECONNRESET, Errno::ENOTCONN, Errno::EBADF
        false
      end
    end

    def start_stream_monitor
      @stream_monitor_thread = Thread.new do
        loop do
          sleep 30 # Check every 30 seconds

          begin
            monitor_streams
          rescue => e
            @configuration.logger.error("Stream monitor error", error: e.message)
          end
        end
      rescue => e
        @configuration.logger.error("Stream monitor thread error", error: e.message)
        sleep 5
        retry
      end
    end

    def monitor_streams
      expired_sessions = @stream_registry.cleanup_expired_streams
      expired_sessions.each do |session_id|
        @session_store.mark_stream_inactive(session_id)
      end

      @stream_registry.get_all_local_streams.each do |session_id, stream|
        if stream_connected?(stream)
          send_ping_to_stream(stream)
          @stream_registry.refresh_heartbeat(session_id)
        else
          close_stream(session_id, reason: "client_disconnected")
        end
      rescue IOError, Errno::EPIPE, Errno::ECONNRESET, Errno::ENOTCONN, Errno::EBADF
        close_stream(session_id, reason: "network_error")
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
      if @stream_registry.has_local_stream?(session_id)
        stream = @stream_registry.get_local_stream(session_id)
        begin
          send_to_stream(stream, data)
          return true
        rescue IOError, Errno::EPIPE, Errno::ECONNRESET
          close_stream(session_id, reason: "client_disconnected")
        end
      end

      @session_store.queue_message_for_session(session_id, data)
    end

    def cleanup_session(session_id)
      @stream_registry.unregister_stream(session_id)
      @session_store.cleanup_session(session_id)
      @request_store.cleanup_session_requests(session_id)
    end

    def start_message_poller
      @message_poller.start
    end

    def has_active_streams?
      @stream_registry.has_any_local_streams?
    end

    def deliver_to_active_streams(notification)
      @stream_registry.get_all_local_streams.each do |session_id, stream|
        send_to_stream(stream, notification)
      rescue IOError, Errno::EPIPE, Errno::ECONNRESET
        close_stream(session_id, reason: "client_disconnected")
      end
    end

    def flush_notifications_to_stream(stream)
      notifications = @notification_queue.pop_all
      notifications.each do |notification|
        send_to_stream(stream, notification)
      end
    end

    # Handle a cancellation notification from the client
    #
    # @param message [Hash] the cancellation notification message
    # @param session_id [String, nil] the session ID if available
    def handle_cancellation(message, session_id = nil)
      params = message["params"]
      return unless params

      request_id = params["requestId"]
      reason = params["reason"]

      return unless request_id

      @request_store.mark_cancelled(request_id, reason)
    rescue
      nil
    end

    def cleanup
      @message_poller&.stop
      @stream_monitor_thread&.kill
      @redis = nil
    end
  end
end
