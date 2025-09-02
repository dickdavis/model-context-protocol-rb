# frozen_string_literal: true

require "json"
require "securerandom"

module ModelContextProtocol
  class Server::StreamableHttpTransport
    def initialize(logger:, router:, configuration:)
      @logger = logger
      @router = router
      @configuration = configuration

      # Redis client is required and provided by user
      transport_options = @configuration.transport_options
      @redis = transport_options[:redis_client]

      @session_store = ModelContextProtocol::Server::SessionStore.new(
        @redis,
        ttl: transport_options[:session_ttl] || 3600
      )

      @server_instance = "#{Socket.gethostname}-#{Process.pid}-#{SecureRandom.hex(4)}"
      @local_streams = {} # session_id => stream

      setup_redis_subscriber
    end

    def handle_request
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
        {json: {error: "Method not allowed"}, status: 405}
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
      {json: {error: "Invalid JSON"}, status: 400}
    rescue => e
      @logger.error("Error handling POST request: #{e.message}")
      @logger.error(e.backtrace)
      {json: {error: "Internal server error"}, status: 500}
    end

    def handle_initialization(body)
      session_id = SecureRandom.uuid

      # Store session with user context
      @session_store.create_session(session_id, {
        server_instance: @server_instance,
        context: @configuration.context || {},
        created_at: Time.now.to_f
      })

      # Process the initialize request
      result = @router.route(body)

      {
        json: result.serialized,
        status: 200,
        headers: {"Mcp-Session-Id" => session_id}
      }
    end

    def handle_regular_request(body, session_id)
      unless session_id && @session_store.session_exists?(session_id)
        return {json: {error: "Invalid or missing session ID"}, status: 400}
      end

      # Process the request
      result = @router.route(body)

      # Check if session has active stream
      if @session_store.session_has_active_stream?(session_id)
        # Send response via SSE stream
        deliver_to_session_stream(session_id, result.serialized)
        {json: {accepted: true}, status: 200}
      else
        # Return response directly
        {json: result.serialized, status: 200}
      end
    end

    def handle_sse_request(request, response)
      session_id = request.headers["Mcp-Session-Id"]

      unless session_id && @session_store.session_exists?(session_id)
        return {json: {error: "Invalid or missing session ID"}, status: 400}
      end

      # Mark session as having active stream
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
        start_keepalive_thread(session_id, stream)

        # Keep connection alive until closed
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
      # Check if stream is still connected
      return false unless stream

      begin
        # Try to write a ping to detect closed connections
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
        @logger.error("Keepalive thread error: #{e.message}")
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
      # Try local stream first
      if @local_streams[session_id]
        begin
          send_to_stream(@local_streams[session_id], data)
          return true
        rescue IOError, Errno::EPIPE, Errno::ECONNRESET
          cleanup_local_stream(session_id)
        end
      end

      # Route via Redis to other servers
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
        @logger.error("Redis subscriber error: #{e.message}")
        @logger.error(e.backtrace)
        # Try to reconnect after a delay
        sleep 5
        retry
      end
    end
  end
end
