require "json"
require "securerandom"
require "concurrent"

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

    attr_reader :server_logger

    # Initialize the HTTP transport with Redis-backed cross-server communication support
    # Sets up background threads for message polling and stream monitoring in multi-server deployments
    def initialize(router:, configuration:)
      @router = router
      @configuration = configuration
      @client_logger = configuration.client_logger
      @server_logger = configuration.server_logger

      @redis_pool = ModelContextProtocol::Server::RedisConfig.pool
      @redis = ModelContextProtocol::Server::RedisClientProxy.new(@redis_pool)

      @require_sessions = @configuration.require_sessions
      # Use Concurrent::Map for thread-safe access from multiple request threads
      @session_protocol_versions = Concurrent::Map.new
      @validate_origin = @configuration.validate_origin
      @allowed_origins = @configuration.allowed_origins

      @session_store = SessionStore.new(@redis, ttl: @configuration.session_ttl)
      @server_instance = "#{Socket.gethostname}-#{Process.pid}-#{SecureRandom.hex(4)}"
      @stream_registry = StreamRegistry.new(@redis, @server_instance)
      @notification_queue = NotificationQueue.new(@redis, @server_instance)
      @event_counter = EventCounter.new(@redis, @server_instance)
      @request_store = RequestStore.new(@redis, @server_instance)
      @server_request_store = ServerRequestStore.new(@redis, @server_instance)
      @ping_timeout = @configuration.ping_timeout

      @message_poller = MessagePoller.new(@redis, @stream_registry, @client_logger) do |stream, message|
        send_to_stream(stream, message)
      end
      @message_poller.start

      @stream_monitor_running = false
      @stream_monitor_thread = nil
      start_stream_monitor
    end

    # Gracefully shut down the transport by stopping background threads and cleaning up resources
    # Closes all active streams. Redis entries are left to expire naturally (they have TTLs).
    # This method is signal-safe and avoids mutex operations.
    def shutdown
      @server_logger.info("Shutting down StreamableHttpTransport")

      @message_poller&.stop

      @stream_monitor_running = false
      if @stream_monitor_thread&.alive?
        @stream_monitor_thread.kill
        @stream_monitor_thread.join(5)
      end

      # Close streams directly without Redis cleanup (signal-safe).
      # Redis entries will expire naturally via TTL.
      @stream_registry.get_all_local_streams.each do |session_id, stream|
        begin
          stream.close
        rescue IOError, Errno::EPIPE, Errno::ECONNRESET, Errno::ENOTCONN, Errno::EBADF
          # Stream already closed, ignore
        end
        @server_logger.info("← SSE stream [closed] (#{session_id}) [shutdown]")
      end

      @server_logger.info("StreamableHttpTransport shutdown complete")
    end

    # Main entry point for handling HTTP requests (POST, GET, DELETE)
    # Routes requests to appropriate handlers and manages the request/response lifecycle
    # @param env [Hash] Rack environment hash (required)
    # @param session_context [Hash] Per-request context that will be merged with server context
    def handle(env:, session_context: {})
      @server_logger.debug("Handling streamable HTTP transport request")

      case env["REQUEST_METHOD"]
      when "POST"
        @server_logger.debug("Handling POST request")
        handle_post_request(env, session_context: session_context)
      when "GET"
        @server_logger.debug("Handling GET request")
        handle_get_request(env)
      when "DELETE"
        @server_logger.debug("Handling DELETE request")
        handle_delete_request(env)
      else
        error_response = ErrorResponse[id: nil, error: {code: -32601, message: "Method not allowed"}]
        {json: error_response.serialized, status: 405}
      end
    end

    # Send real-time notifications to active SSE streams or queue for delivery
    # Used for progress updates, resource changes, and other server-initiated messages
    # @param method [String] the notification method name
    # @param params [Hash] the notification parameters
    # @param session_id [String, nil] optional session ID for targeted delivery
    def send_notification(method, params, session_id: nil)
      notification = {
        jsonrpc: "2.0",
        method: method,
        params: params
      }

      log_to_server_with_context do |logger|
        logger.info("← #{method} [outgoing]")
        logger.info("  Notification: #{notification.to_json}")
      end

      if session_id
        # Deliver to specific session/stream
        @server_logger.debug("Attempting targeted delivery to session: #{session_id}")
        if deliver_to_session_stream(session_id, notification)
          @server_logger.debug("Successfully delivered notification to specific stream: #{session_id}")
        else
          @server_logger.debug("Failed to deliver to specific stream #{session_id}, queuing notification: #{method}")
          @notification_queue.push(notification)
        end
      elsif @stream_registry.get_local_stream(nil) # Check for persistent notification stream (no-session)
        @server_logger.debug("No session_id provided, delivering notification to persistent notification stream")
        if deliver_to_session_stream(nil, notification)
          @server_logger.debug("Successfully delivered notification to persistent notification stream")
        else
          @server_logger.debug("Failed to deliver to persistent notification stream, queuing notification: #{method}")
          @notification_queue.push(notification)
        end
      elsif @stream_registry.has_any_local_streams?
        @server_logger.debug("No persistent notification stream, delivering notification to active streams")
        deliver_to_active_streams(notification)
      else
        @server_logger.debug("No active streams, queuing notification: #{method}")
        @notification_queue.push(notification)
      end
    end

    private

    # Provide logging context with request ID and MCP context information
    # Ensures consistent logging format across all transport operations
    def log_to_server_with_context(request_id: nil, &block)
      original_context = Thread.current[:mcp_context]
      if request_id && !Thread.current[:mcp_context]
        Thread.current[:mcp_context] = {jsonrpc_request_id: request_id}
      end

      begin
        block.call(@server_logger) if block_given?
      ensure
        Thread.current[:mcp_context] = original_context if request_id && original_context.nil?
      end
    end

    # Validate HTTP headers for POST requests: CORS origin, content type, and protocol version.
    # Returns error response hash if headers are invalid, nil if valid.
    def validate_headers(env, session_id: nil)
      origin_error = validate_origin!(env)
      return origin_error if origin_error

      accept_header = env["HTTP_ACCEPT"]
      if accept_header
        unless accept_header.include?("application/json") || accept_header.include?("text/event-stream")
          error_response = ErrorResponse[id: nil, error: {code: -32600, message: "Invalid Accept header. Must include application/json or text/event-stream"}]
          return {json: error_response.serialized, status: 400}
        end
      end

      validate_protocol_version!(env, session_id: session_id)
    end

    # Validate CORS Origin header against allowed origins.
    # The MCP spec requires servers to validate Origin on all incoming connections
    # to prevent DNS rebinding attacks.
    def validate_origin!(env)
      return nil unless @validate_origin

      origin = env["HTTP_ORIGIN"]
      if origin && !@allowed_origins.any? { |allowed| origin.start_with?(allowed) }
        error_response = ErrorResponse[id: nil, error: {code: -32600, message: "Origin not allowed"}]
        return {json: error_response.serialized, status: 403}
      end

      nil
    end

    # Validate MCP-Protocol-Version header against negotiated version.
    # Per the MCP spec, the server MUST respond with 400 Bad Request for invalid
    # or unsupported protocol versions. When a session_id is provided, validation
    # is scoped to that session's negotiated version.
    def validate_protocol_version!(env, session_id: nil)
      protocol_version = env["HTTP_MCP_PROTOCOL_VERSION"]
      return nil unless protocol_version

      # When a session_id is provided, try session-specific validation first.
      # If the session has a known negotiated version, validate strictly against it.
      if session_id
        expected_version = @session_protocol_versions[session_id]
        if expected_version
          if protocol_version != expected_version
            error_response = ErrorResponse[id: nil, error: {code: -32600, message: "Invalid MCP protocol version: #{protocol_version}. Expected: #{expected_version}"}]
            return {json: error_response.serialized, status: 400}
          end
          return nil
        end
      end

      # Fallback: validate against all known negotiated versions (covers cases
      # where session_id is nil or has no entry, e.g. sessions not required).
      valid_versions = @session_protocol_versions.values.compact.uniq
      unless valid_versions.empty? || valid_versions.include?(protocol_version)
        error_response = ErrorResponse[id: nil, error: {code: -32600, message: "Invalid MCP protocol version: #{protocol_version}. Expected one of: #{valid_versions.join(", ")}"}]
        return {json: error_response.serialized, status: 400}
      end

      nil
    end

    # Determine JSON-RPC message type from request body structure
    # Classifies messages as request, notification, response, or unknown
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

    # Handle HTTP POST requests containing JSON-RPC messages
    # Parses request body and routes to initialization or regular request handlers
    # @param env [Hash] Rack environment hash
    # @param session_context [Hash] Per-request context for initialization
    def handle_post_request(env, session_context: {})
      session_id = env["HTTP_MCP_SESSION_ID"]
      validation_error = validate_headers(env, session_id: session_id)
      return validation_error if validation_error

      body_string = env["rack.input"].read
      body = JSON.parse(body_string)
      accept_header = env["HTTP_ACCEPT"] || ""

      log_to_server_with_context(request_id: body["id"]) do |logger|
        method = body["method"]
        id = body["id"]

        if method&.start_with?("notifications/") || id.nil?
          logger.info("→ #{method} [notification]")
        else
          logger.info("→ #{method} (id: #{id}) [request]")
        end

        logger.info("  Request: #{body.to_json}")
        logger.debug("  Accept: #{accept_header}") if body["method"] != "notifications/initialized"
        logger.debug("  Redis Pool: #{ModelContextProtocol::Server::RedisConfig.stats}")
      end

      if body["method"] == "initialize"
        handle_initialization(body, accept_header, session_context: session_context)
      else
        handle_regular_request(body, session_id, accept_header)
      end
    rescue JSON::ParserError => e
      log_to_server_with_context do |logger|
        logger.error("JSON parse error in streamable HTTP transport: #{e.message}")
      end
      error_response = ErrorResponse[id: "", error: {code: -32700, message: "Parse error"}]
      log_to_server_with_context do |logger|
        logger.info("← Error response (code: #{error_response.error[:code]})")
        logger.info("  #{error_response.serialized.to_json}")
      end
      {json: error_response.serialized, status: 400}
    rescue ModelContextProtocol::Server::ParameterValidationError => validation_error
      log_to_server_with_context(request_id: body&.dig("id")) do |logger|
        logger.error("Parameter validation failed in streamable HTTP transport: #{validation_error.message}")
      end
      error_response = ErrorResponse[id: body&.dig("id"), error: {code: -32602, message: validation_error.message}]
      log_to_server_with_context(request_id: error_response.id) do |logger|
        logger.info("← Error response (code: #{error_response.error[:code]})")
        logger.info("  #{error_response.serialized.to_json}")
      end
      {json: error_response.serialized, status: 400}
    rescue => e
      log_to_server_with_context(request_id: body&.dig("id")) do |logger|
        logger.error("Internal error handling POST request in streamable HTTP transport: #{e.message}")
        logger.debug("Backtrace: #{e.backtrace.join("\n")}")
      end
      error_response = ErrorResponse[id: body&.dig("id"), error: {code: -32603, message: "Internal error"}]
      log_to_server_with_context(request_id: error_response.id) do |logger|
        logger.info("← Error response (code: #{error_response.error[:code]})")
        logger.info("  #{error_response.serialized.to_json}")
      end
      {json: error_response.serialized, status: 500}
    end

    # Handle MCP initialization requests to establish protocol version and optional sessions
    # Always returns JSON response regardless of Accept header to keep initialization simple
    # @param body [Hash] Parsed JSON-RPC request body
    # @param accept_header [String] HTTP Accept header value
    # @param session_context [Hash] Per-request context to merge with server context
    def handle_initialization(body, accept_header, session_context: {})
      result = @router.route(body, transport: self)
      response = Response[id: body["id"], result: result.serialized]
      response_headers = {}
      negotiated_protocol_version = result.serialized[:protocolVersion] || result.serialized["protocolVersion"]

      if @require_sessions
        session_id = SecureRandom.uuid
        # Merge server-level defaults with request-level context
        merged_context = (@configuration.context || {}).merge(session_context)
        @session_store.create_session(session_id, {
          server_instance: @server_instance,
          context: merged_context,
          created_at: Time.now.to_f,
          negotiated_protocol_version: negotiated_protocol_version
        })
        # Store initial handler names for list_changed detection
        current_handlers = @configuration.registry.handler_names
        @session_store.store_registered_handlers(session_id, **current_handlers)
        response_headers["Mcp-Session-Id"] = session_id
        @session_protocol_versions[session_id] = negotiated_protocol_version
        log_to_server_with_context { |logger| logger.info("Session created: #{session_id} (protocol: #{negotiated_protocol_version})") }
      else
        @session_protocol_versions[:default] = negotiated_protocol_version
      end

      response_headers["Content-Type"] = "application/json"

      log_to_server_with_context(request_id: response.id) do |logger|
        logger.info("← #{body["method"]} Response")
        logger.info("  #{response.serialized.to_json}")
      end

      {
        json: response.serialized,
        status: 200,
        headers: response_headers
      }
    end

    # Handle regular MCP requests (tools, resources, prompts) with streaming/JSON decision logic
    # Defaults to SSE streaming but returns JSON when client explicitly requests JSON only
    def handle_regular_request(body, session_id, accept_header)
      session_context = {}

      if @require_sessions
        # Per the MCP spec, servers SHOULD respond to requests without a valid
        # Mcp-Session-Id header (other than initialization) with HTTP 400.
        # The session ID MUST be present on all subsequent requests after initialization,
        # including notifications like notifications/initialized.
        unless session_id && @session_store.session_exists?(session_id)
          if session_id
            error_response = ErrorResponse[id: body["id"], error: {code: -32600, message: "Session terminated"}]
            return {json: error_response.serialized, status: 404}
          else
            error_response = ErrorResponse[id: body["id"], error: {code: -32600, message: "Invalid or missing session ID"}]
            return {json: error_response.serialized, status: 400}
          end
        end

        session_context = @session_store.get_session_context(session_id)
        check_and_notify_handler_changes(session_id)
      end

      message_type = determine_message_type(body)

      case message_type
      when :notification, :response
        if body["method"] == "notifications/cancelled"
          handle_cancellation(body, session_id)
        elsif message_type == :response && handle_ping_response(body)
          # Ping response handled, don't forward to streams
          log_to_server_with_context do |logger|
            logger.info("← Ping response [accepted]")
          end
        elsif session_id && @session_store.session_has_active_stream?(session_id)
          deliver_to_session_stream(session_id, body)
        elsif message_type == :response
          # This might be a ping response for an expired session
          log_to_server_with_context do |logger|
            logger.debug("← Response for expired/unknown session: #{session_id}")
          end
        end
        log_to_server_with_context do |logger|
          logger.info("← Notification [accepted]")
        end
        {status: 202}

      when :request
        if accept_header.include?("text/event-stream")
          {
            stream: true,
            headers: {
              "Content-Type" => "text/event-stream",
              "Cache-Control" => "no-cache",
              "Connection" => "keep-alive"
            },
            stream_proc: create_request_response_sse_stream_proc(body, session_id, session_context: session_context)
          }
        elsif (result = @router.route(body, request_store: @request_store, session_id: session_id, transport: self, session_context: session_context))
          response = Response[id: body["id"], result: result.serialized]

          log_to_server_with_context(request_id: response.id) do |logger|
            logger.info("← #{body["method"]} Response")
            logger.info("  #{response.serialized.to_json}")
          end

          {
            json: response.serialized,
            status: 200,
            headers: {"Content-Type" => "application/json"}
          }
        else
          log_to_server_with_context do |logger|
            logger.info("← Response (status: 204)")
          end
          {json: {}, status: 204}
        end
      end
    end

    # Handle HTTP GET requests to establish persistent SSE connections for notifications
    # Validates session requirements and Accept headers before opening long-lived streams
    def handle_get_request(env)
      origin_error = validate_origin!(env)
      return origin_error if origin_error

      accept_header = env["HTTP_ACCEPT"] || ""
      unless accept_header.include?("text/event-stream")
        error_response = ErrorResponse[id: nil, error: {code: -32600, message: "Accept header must include text/event-stream"}]
        return {json: error_response.serialized, status: 400}
      end

      session_id = env["HTTP_MCP_SESSION_ID"]

      protocol_error = validate_protocol_version!(env, session_id: session_id)
      return protocol_error if protocol_error

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
        stream_proc: create_persistent_notification_sse_stream_proc(session_id, last_event_id)
      }
    end

    # Handle HTTP DELETE requests to clean up sessions and associated resources
    # Removes session data, closes streams, and cleans up request store entries
    def handle_delete_request(env)
      origin_error = validate_origin!(env)
      return origin_error if origin_error

      session_id = env["HTTP_MCP_SESSION_ID"]

      protocol_error = validate_protocol_version!(env, session_id: session_id)
      return protocol_error if protocol_error

      @server_logger.info("→ DELETE /mcp [Session cleanup: #{session_id || "unknown"}]")

      if @require_sessions
        unless session_id
          error_response = ErrorResponse[id: nil, error: {code: -32600, message: "Invalid or missing session ID"}]
          return {json: error_response.serialized, status: 400}
        end

        unless @session_store.session_exists?(session_id)
          error_response = ErrorResponse[id: nil, error: {code: -32600, message: "Session terminated"}]
          return {json: error_response.serialized, status: 404}
        end
      end

      if session_id
        cleanup_session(session_id)
        log_to_server_with_context { |logger| logger.info("Session cleanup: #{session_id}") }
      end

      log_to_server_with_context do |logger|
        logger.info("← DELETE Response")
        logger.info("  #{{"success" => true}.to_json}")
      end
      {json: {success: true}, status: 200}
    end

    # Create SSE stream processor for request-response pattern with real-time progress support
    # Opens stream → Executes request → Sends response → Closes stream
    # Enables progress notifications during long-running operations like tool calls
    # @param request_body [Hash] Parsed JSON-RPC request
    # @param session_id [String, nil] Session ID for this request
    # @param session_context [Hash] Context to pass to handlers
    def create_request_response_sse_stream_proc(request_body, session_id, session_context: {})
      proc do |stream|
        temp_stream_id = "temp-#{SecureRandom.hex(8)}"
        @stream_registry.register_stream(temp_stream_id, stream)

        log_to_server_with_context(request_id: request_body["id"]) do |logger|
          logger.info("← SSE stream [opened] (#{temp_stream_id})")
          logger.info("  Connection will remain open for real-time notifications")
        end

        begin
          if (result = @router.route(request_body, request_store: @request_store, session_id: session_id, transport: self, stream_id: temp_stream_id, session_context: session_context))
            response = Response[id: request_body["id"], result: result.serialized]
            event_id = next_event_id
            send_sse_event(stream, response.serialized, event_id)
            @server_logger.debug("Sent response via SSE stream (id: #{request_body["id"]})")
          else
            event_id = next_event_id
            send_sse_event(stream, {}, event_id)
            @server_logger.debug("Sent empty response via SSE stream (id: #{request_body["id"]})")
          end

          close_stream(temp_stream_id, reason: "request_completed")
        rescue IOError, Errno::EPIPE, Errno::ECONNRESET => e
          @server_logger.debug("Client disconnected during progressive request processing: #{e.class.name}")
          log_to_server_with_context { |logger| logger.info("← SSE stream [closed] (#{temp_stream_id}) [client_disconnected]") }
        rescue ModelContextProtocol::Server::ParameterValidationError => e
          @client_logger.error("Validation error", error: e.message)
          error_response = ErrorResponse[id: request_body["id"], error: {code: -32602, message: e.message}]
          send_sse_event(stream, error_response.serialized, next_event_id)
          close_stream(temp_stream_id, reason: "validation_error")
        rescue => e
          @client_logger.error("Internal error", error: e.message, backtrace: e.backtrace)
          error_response = ErrorResponse[id: request_body["id"], error: {code: -32603, message: e.message}]
          send_sse_event(stream, error_response.serialized, next_event_id)
          close_stream(temp_stream_id, reason: "internal_error")
        ensure
          @stream_registry.unregister_stream(temp_stream_id)
        end
      end
    end

    # Generate unique sequential event IDs for SSE streams
    # Enables client-side event replay and ordering guarantees
    def next_event_id
      @event_counter.next_event_id
    end

    # Send formatted SSE event to stream with optional event ID
    # Handles JSON serialization and proper SSE formatting with data/id fields
    def send_sse_event(stream, data, event_id = nil)
      if event_id
        stream.write("id: #{event_id}\n")
      end
      message = data.is_a?(String) ? data : data.to_json
      stream.write("data: #{message}\n\n")
      stream.flush if stream.respond_to?(:flush)
    end

    # Close an active SSE stream and clean up associated resources
    # Unregisters from stream registry and marks session inactive
    def close_stream(session_id, reason: "completed")
      if (stream = @stream_registry.get_local_stream(session_id))
        begin
          stream.close
        rescue IOError, Errno::EPIPE, Errno::ECONNRESET, Errno::ENOTCONN, Errno::EBADF
          nil
        end

        reason_text = reason ? " [#{reason}]" : ""
        log_to_server_with_context { |logger| logger.info("← SSE stream [closed] (#{session_id})#{reason_text}") }
        @stream_registry.unregister_stream(session_id)
        @session_store.mark_stream_inactive(session_id) if @require_sessions
      end
    end

    # Create SSE stream processor for long-lived notification streams
    # Opens stream → Keeps connection alive → Receives notifications over time
    # Supports event replay from last_event_id for client reconnection scenarios
    def create_persistent_notification_sse_stream_proc(session_id, last_event_id = nil)
      proc do |stream|
        @stream_registry.register_stream(session_id, stream) if session_id

        log_to_server_with_context do |logger|
          logger.info("← SSE stream [opened] (#{session_id || "no-session"})")
          logger.info("  Connection will remain open for real-time notifications")
        end

        if last_event_id
          replay_messages_after_event_id(stream, session_id, last_event_id)
        else
          flush_notifications_to_stream(stream)
        end

        # Also flush any messages queued in Redis from other server instances
        poll_and_deliver_redis_messages(stream, session_id) if session_id

        loop do
          break unless stream_connected?(stream)

          # Poll for queued messages from Redis (cross-server delivery)
          poll_and_deliver_redis_messages(stream, session_id) if session_id

          sleep 0.1
        end
      ensure
        if session_id
          log_to_server_with_context { |logger| logger.info("← SSE stream [closed] (#{session_id}) [loop_ended]") }
          @stream_registry.unregister_stream(session_id)
        end
      end
    end

    # Test if an SSE stream is still connected by checking its status
    # Returns false if stream has been disconnected due to network issues
    # Actual connectivity testing is done via MCP ping requests in monitor_streams
    def stream_connected?(stream)
      return false unless stream

      begin
        # Check if stream reports as closed first (quick check)
        if stream.respond_to?(:closed?) && stream.closed?
          return false
        end

        true
      rescue IOError, Errno::EPIPE, Errno::ECONNRESET, Errno::ENOTCONN, Errno::EBADF
        false
      end
    end

    # Start background thread to monitor stream health and clean up disconnected streams
    # Runs every 30 seconds to detect client disconnections and prevent resource leaks
    def start_stream_monitor
      @stream_monitor_running = true
      @stream_monitor_thread = Thread.new do
        while @stream_monitor_running
          # Sleep in 1-second intervals to allow quick shutdown response
          30.times do
            break unless @stream_monitor_running
            sleep 1
          end

          next unless @stream_monitor_running

          begin
            monitor_streams
          rescue => e
            @server_logger.error("Stream monitor error: #{e.message}")
          end
        end
      end
    end

    # Monitor all active streams for connectivity and clean up expired/disconnected ones
    # Sends ping messages and removes streams that fail to respond
    def monitor_streams
      expired_sessions = @stream_registry.cleanup_expired_streams
      unless expired_sessions.empty?
        @server_logger.debug("Cleaned up #{expired_sessions.size} expired streams: #{expired_sessions.join(", ")}")
      end

      expired_sessions.each do |session_id|
        @session_store.mark_stream_inactive(session_id)
      end

      # Check for expired ping requests and close unresponsive streams
      expired_pings = @server_request_store.get_expired_requests(@ping_timeout)
      unless expired_pings.empty?
        @server_logger.debug("Found #{expired_pings.size} expired ping requests")
        expired_pings.each do |ping_info|
          session_id = ping_info[:session_id]
          request_id = ping_info[:request_id]
          age = ping_info[:age]

          @server_logger.warn("Ping timeout for session #{session_id} (request: #{request_id}, age: #{age.round(2)}s)")
          close_stream(session_id, reason: "ping_timeout")
          @server_request_store.unregister_request(request_id)
        end
      end

      @stream_registry.get_all_local_streams.each do |session_id, stream|
        if stream_connected?(stream)
          send_ping_to_stream(stream, session_id)
          @stream_registry.refresh_heartbeat(session_id)
        else
          @server_logger.debug("Stream disconnected during monitoring: #{session_id}")
          close_stream(session_id, reason: "client_disconnected")
        end
      rescue IOError, Errno::EPIPE, Errno::ECONNRESET, Errno::ENOTCONN, Errno::EBADF => e
        @server_logger.debug("Network error during stream monitoring for #{session_id}: #{e.class.name}")
        close_stream(session_id, reason: "network_error")
      end
    end

    # Send MCP-compliant ping request to test connectivity and expect response
    # Tracks the ping in server request store for timeout detection
    def send_ping_to_stream(stream, session_id)
      ping_id = "ping-#{SecureRandom.hex(8)}"
      ping_request = {
        jsonrpc: "2.0",
        id: ping_id,
        method: "ping"
      }

      @server_request_store.register_request(ping_id, session_id, type: :ping)
      send_to_stream(stream, ping_request)

      @server_logger.debug("Sent MCP ping request (id: #{ping_id}) to stream: #{session_id}")
    end

    # Send data to an SSE stream with proper event formatting and error handling
    # Automatically closes stream on connection errors to prevent resource leaks
    def send_to_stream(stream, data)
      event_id = next_event_id
      send_sse_event(stream, data, event_id)
    end

    # Replay missed messages from Redis after client reconnection
    # Enables clients to catch up on messages they missed during disconnection
    def replay_messages_after_event_id(stream, session_id, last_event_id)
      flush_notifications_to_stream(stream)
    end

    # Deliver data to a specific session's stream or queue for cross-server delivery
    # Handles both local stream delivery and cross-server message queuing
    # @return [Boolean] true if delivered to active stream, false if queued
    def deliver_to_session_stream(session_id, data)
      if @stream_registry.has_local_stream?(session_id)
        stream = @stream_registry.get_local_stream(session_id)
        begin
          # MANDATORY connection validation before every delivery
          @server_logger.debug("Validating stream connection for #{session_id}")
          unless stream_connected?(stream)
            @server_logger.warn("Stream #{session_id} failed connection validation - cleaning up")
            close_stream(session_id, reason: "connection_validation_failed")
            return false
          end

          @server_logger.debug("Stream #{session_id} passed connection validation")
          send_to_stream(stream, data)
          @server_logger.debug("Successfully delivered message to active stream: #{session_id}")
          return true
        rescue IOError, Errno::EPIPE, Errno::ECONNRESET, Errno::ENOTCONN, Errno::EBADF => e
          @server_logger.warn("Failed to deliver to stream #{session_id}, network error: #{e.class.name}")
          close_stream(session_id, reason: "network_error")
          return false
        end
      end

      @server_logger.debug("No local stream found for session #{session_id}, queuing message")
      @session_store.queue_message_for_session(session_id, data)
      false
    end

    # Clean up all resources associated with a session
    # Removes from stream registry, session store, request store, and server request store
    def cleanup_session(session_id)
      @stream_registry.unregister_stream(session_id)
      @session_store.cleanup_session(session_id)
      @request_store.cleanup_session_requests(session_id)
      @server_request_store.cleanup_session_requests(session_id)
    end

    # Check if this transport instance has any active local streams
    # Used to determine if notifications should be queued or delivered immediately
    def has_active_streams?
      @stream_registry.has_any_local_streams?
    end

    # Broadcast notification to all active streams on this transport instance
    # Handles connection errors gracefully and removes disconnected streams
    def deliver_to_active_streams(notification)
      delivered_count = 0
      disconnected_streams = []

      @stream_registry.get_all_local_streams.each do |session_id, stream|
        # Verify stream is still connected before attempting delivery
        unless stream_connected?(stream)
          disconnected_streams << session_id
          next
        end

        send_to_stream(stream, notification)
        delivered_count += 1
        @server_logger.debug("Delivered notification to stream: #{session_id}")
      rescue IOError, Errno::EPIPE, Errno::ECONNRESET, Errno::ENOTCONN, Errno::EBADF => e
        @server_logger.debug("Failed to deliver notification to stream #{session_id}, client disconnected: #{e.class.name}")
        disconnected_streams << session_id
      end

      # Clean up disconnected streams
      disconnected_streams.each do |session_id|
        close_stream(session_id, reason: "client_disconnected")
      end

      @server_logger.debug("Delivered notifications to #{delivered_count} streams, cleaned up #{disconnected_streams.size} disconnected streams")
    end

    # Poll for messages queued in Redis and deliver to the stream
    # Handles cross-server message delivery when notifications are queued by other server instances
    def poll_and_deliver_redis_messages(stream, session_id)
      return unless session_id

      messages = @session_store.poll_messages_for_session(session_id)
      return if messages.empty?

      @server_logger.debug("Delivering #{messages.size} queued messages from Redis to stream #{session_id}")
      messages.each do |message|
        send_to_stream(stream, message)
      end
    rescue => e
      @server_logger.error("Error polling Redis messages: #{e.message}")
    end

    # Flush any queued notifications to a newly connected stream
    # Ensures clients receive notifications that were queued while disconnected
    def flush_notifications_to_stream(stream)
      notifications = @notification_queue.pop_all
      @server_logger.debug("Checking notification queue: #{notifications.size} notifications queued")
      if notifications.empty?
        @server_logger.debug("No queued notifications to flush")
      else
        @server_logger.debug("Flushing #{notifications.size} queued notifications to new stream")
        notifications.each do |notification|
          send_to_stream(stream, notification)
          @server_logger.debug("Flushed queued notification: #{notification[:method]}")
        end
      end
    end

    # Handle ping responses from clients to mark server-initiated ping requests as completed
    # Returns true if this was a ping response, false otherwise
    def handle_ping_response(message)
      response_id = message["id"]
      return false unless response_id

      # Check if this response ID corresponds to a pending ping request
      if @server_request_store.pending?(response_id)
        request_info = @server_request_store.get_request(response_id)
        if request_info && request_info["type"] == "ping"
          @server_request_store.mark_completed(response_id)
          @server_logger.debug("Received ping response for request: #{response_id}")
          return true
        end
      end

      false
    rescue => e
      @server_logger.error("Error processing ping response: #{e.message}")
      false
    end

    # Handle client cancellation requests to abort in-progress operations
    # Marks requests as cancelled in the request store to stop ongoing work
    def handle_cancellation(message, session_id = nil)
      params = message["params"]
      return unless params

      jsonrpc_request_id = params["requestId"]
      reason = params["reason"]

      return unless jsonrpc_request_id

      log_to_server_with_context(request_id: jsonrpc_request_id) do |logger|
        logger.info("Processing cancellation (reason: #{reason || "unknown"})")
      end

      @request_store.mark_cancelled(jsonrpc_request_id, reason)
    rescue => e
      log_to_server_with_context(request_id: jsonrpc_request_id) do |logger|
        logger.error("Error processing cancellation: #{e.message}")
      end
      nil
    end

    # Check if registered handlers have changed for a session and send notifications
    # Compares current handlers against previously stored handlers in Redis
    def check_and_notify_handler_changes(session_id)
      return unless session_id
      return unless @session_store.session_exists?(session_id)

      current = @configuration.registry.handler_names
      previous = @session_store.get_registered_handlers(session_id)

      return if previous.nil? # First request after init

      changed_types = []
      changed_types << :prompts if current[:prompts].sort != previous[:prompts]&.sort
      changed_types << :resources if current[:resources].sort != previous[:resources]&.sort
      changed_types << :tools if current[:tools].sort != previous[:tools]&.sort

      return if changed_types.empty?

      changed_types.each do |type|
        send_notification("notifications/#{type}/list_changed", {}, session_id: session_id)
      end

      @session_store.store_registered_handlers(session_id, **current)
    rescue => e
      @server_logger.error("Error checking handler changes: #{e.class.name}: #{e.message}")
      @server_logger.debug("Backtrace: #{e.backtrace.first(5).join("\n")}")
      # Don't re-raise - handler change detection is optional, allow request to proceed
    end
  end
end
