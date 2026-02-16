require "json"

module ModelContextProtocol
  class Server::StreamableHttpTransport
    # Redis-based distributed storage for tracking active requests and their cancellation status.
    # This store is used by StreamableHttpTransport to manage request lifecycle across multiple
    # server instances and handle cancellation in a distributed environment.
    class RequestStore
      REQUEST_KEY_PREFIX = "request:active:"
      CANCELLED_KEY_PREFIX = "request:cancelled:"
      SESSION_KEY_PREFIX = "request:session:"
      DEFAULT_TTL = 60  # 1 minute TTL for request entries

      def initialize(redis_client, server_instance, ttl: DEFAULT_TTL)
        @redis = redis_client
        @server_instance = server_instance
        @ttl = ttl
      end

      # Register a new request with its associated session
      #
      # @param jsonrpc_request_id [String] the unique JSON-RPC request identifier
      # @param session_id [String] the session identifier (can be nil for sessionless requests)
      # @return [void]
      def register_request(jsonrpc_request_id, session_id = nil)
        request_data = {
          session_id: session_id,
          server_instance: @server_instance,
          started_at: Time.now.to_f
        }

        @redis.multi do |multi|
          multi.set("#{REQUEST_KEY_PREFIX}#{jsonrpc_request_id}",
            request_data.to_json, ex: @ttl)

          if session_id
            multi.set("#{SESSION_KEY_PREFIX}#{session_id}:#{jsonrpc_request_id}",
              true, ex: @ttl)
          end
        end
      end

      # Mark a request as cancelled
      #
      # @param jsonrpc_request_id [String] the unique JSON-RPC request identifier
      # @param reason [String] optional reason for cancellation
      # @return [Boolean] true if cancellation was recorded
      def mark_cancelled(jsonrpc_request_id, reason = nil)
        cancellation_data = {
          cancelled_at: Time.now.to_f,
          reason: reason
        }

        result = @redis.set("#{CANCELLED_KEY_PREFIX}#{jsonrpc_request_id}",
          cancellation_data.to_json, ex: @ttl)
        result == "OK"
      end

      # Check if a request has been cancelled
      #
      # @param jsonrpc_request_id [String] the unique JSON-RPC request identifier
      # @return [Boolean] true if the request is cancelled, false otherwise
      def cancelled?(jsonrpc_request_id)
        @redis.exists("#{CANCELLED_KEY_PREFIX}#{jsonrpc_request_id}") == 1
      end

      # Unregister a request (typically called when request completes)
      #
      # @param jsonrpc_request_id [String] the unique JSON-RPC request identifier
      # @return [void]
      def unregister_request(jsonrpc_request_id)
        request_data = @redis.get("#{REQUEST_KEY_PREFIX}#{jsonrpc_request_id}")

        keys_to_delete = ["#{REQUEST_KEY_PREFIX}#{jsonrpc_request_id}",
          "#{CANCELLED_KEY_PREFIX}#{jsonrpc_request_id}"]

        if request_data
          begin
            data = JSON.parse(request_data)
            session_id = data["session_id"]

            if session_id
              keys_to_delete << "#{SESSION_KEY_PREFIX}#{session_id}:#{jsonrpc_request_id}"
            end
          rescue JSON::ParserError
            nil
          end
        end

        @redis.del(*keys_to_delete) unless keys_to_delete.empty?
      end

      # Clean up all requests associated with a session
      # This is typically called when a session is terminated
      #
      # @param session_id [String] the session identifier
      # @return [Array<String>] list of cleaned up request IDs
      def cleanup_session_requests(session_id)
        pattern = "#{SESSION_KEY_PREFIX}#{session_id}:*"
        request_keys = @redis.keys(pattern)
        return [] if request_keys.empty?

        # Extract request IDs from the keys
        jsonrpc_request_ids = request_keys.map do |key|
          key.sub("#{SESSION_KEY_PREFIX}#{session_id}:", "")
        end

        # Delete all related keys
        all_keys = []
        jsonrpc_request_ids.each do |jsonrpc_request_id|
          all_keys << "#{REQUEST_KEY_PREFIX}#{jsonrpc_request_id}"
          all_keys << "#{CANCELLED_KEY_PREFIX}#{jsonrpc_request_id}"
        end
        all_keys.concat(request_keys)

        @redis.del(*all_keys) unless all_keys.empty?
        jsonrpc_request_ids
      end
    end
  end
end
