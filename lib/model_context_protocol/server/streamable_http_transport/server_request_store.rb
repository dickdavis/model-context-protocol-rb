require "json"

module ModelContextProtocol
  class Server::StreamableHttpTransport
    # Redis-based distributed storage for tracking server-initiated requests and their response status.
    # This store is used by StreamableHttpTransport to manage outgoing request lifecycle (like pings)
    # across multiple server instances and handle timeouts in a distributed environment.
    class ServerRequestStore
      REQUEST_KEY_PREFIX = "server_request:pending:"
      SESSION_KEY_PREFIX = "server_request:session:"
      DEFAULT_TTL = 60  # 1 minute TTL for request entries

      def initialize(redis_client, server_instance, ttl: DEFAULT_TTL)
        @redis = redis_client
        @server_instance = server_instance
        @ttl = ttl
      end

      # Register a new server-initiated request with its associated session
      #
      # @param request_id [String] the unique JSON-RPC request identifier
      # @param session_id [String] the session identifier (can be nil for sessionless requests)
      # @param type [Symbol] the type of request (e.g., :ping)
      # @return [void]
      def register_request(request_id, session_id = nil, type: :ping)
        request_data = {
          session_id: session_id,
          server_instance: @server_instance,
          type: type.to_s,
          created_at: Time.now.to_f
        }

        @redis.multi do |multi|
          multi.set("#{REQUEST_KEY_PREFIX}#{request_id}",
            request_data.to_json, ex: @ttl)

          if session_id
            multi.set("#{SESSION_KEY_PREFIX}#{session_id}:#{request_id}",
              true, ex: @ttl)
          end
        end
      end

      # Mark a server-initiated request as completed (response received)
      #
      # @param request_id [String] the unique JSON-RPC request identifier
      # @return [Boolean] true if request was pending, false if not found
      def mark_completed(request_id)
        request_data = @redis.get("#{REQUEST_KEY_PREFIX}#{request_id}")
        return false unless request_data

        unregister_request(request_id)
        true
      end

      # Check if a server-initiated request is still pending
      #
      # @param request_id [String] the unique JSON-RPC request identifier
      # @return [Boolean] true if the request is pending, false otherwise
      def pending?(request_id)
        @redis.exists("#{REQUEST_KEY_PREFIX}#{request_id}") == 1
      end

      # Get information about a specific pending request
      #
      # @param request_id [String] the unique JSON-RPC request identifier
      # @return [Hash, nil] request information or nil if not found
      def get_request(request_id)
        data = @redis.get("#{REQUEST_KEY_PREFIX}#{request_id}")
        data ? JSON.parse(data) : nil
      rescue JSON::ParserError
        nil
      end

      # Find requests that have exceeded the specified timeout
      #
      # @param timeout_seconds [Integer] timeout in seconds
      # @return [Array<Hash>] array of expired request info with request_id and session_id
      def get_expired_requests(timeout_seconds)
        current_time = Time.now.to_f
        expired_requests = []

        # Get all pending request keys
        request_keys = @redis.keys("#{REQUEST_KEY_PREFIX}*")
        return expired_requests if request_keys.empty?

        # Get all request data in batch
        request_values = @redis.mget(request_keys)

        request_keys.each_with_index do |key, index|
          next unless request_values[index]

          begin
            request_data = JSON.parse(request_values[index])
            created_at = request_data["created_at"]

            if created_at && (current_time - created_at) > timeout_seconds
              request_id = key.sub(REQUEST_KEY_PREFIX, "")
              expired_requests << {
                request_id: request_id,
                session_id: request_data["session_id"],
                type: request_data["type"],
                age: current_time - created_at
              }
            end
          rescue JSON::ParserError
            # Skip malformed entries
            next
          end
        end

        expired_requests
      end

      # Clean up expired requests based on timeout
      #
      # @param timeout_seconds [Integer] timeout in seconds
      # @return [Array<String>] list of cleaned up request IDs
      def cleanup_expired_requests(timeout_seconds)
        expired_requests = get_expired_requests(timeout_seconds)

        expired_requests.each do |request_info|
          unregister_request(request_info[:request_id])
        end

        expired_requests.map { |r| r[:request_id] }
      end

      # Unregister a request (typically called when request completes or times out)
      #
      # @param request_id [String] the unique JSON-RPC request identifier
      # @return [void]
      def unregister_request(request_id)
        request_data = @redis.get("#{REQUEST_KEY_PREFIX}#{request_id}")

        keys_to_delete = ["#{REQUEST_KEY_PREFIX}#{request_id}"]

        if request_data
          begin
            data = JSON.parse(request_data)
            session_id = data["session_id"]

            if session_id
              keys_to_delete << "#{SESSION_KEY_PREFIX}#{session_id}:#{request_id}"
            end
          rescue JSON::ParserError
            nil
          end
        end

        @redis.del(*keys_to_delete) unless keys_to_delete.empty?
      end

      # Clean up all server requests associated with a session
      # This is typically called when a session is terminated
      #
      # @param session_id [String] the session identifier
      # @return [Array<String>] list of cleaned up request IDs
      def cleanup_session_requests(session_id)
        pattern = "#{SESSION_KEY_PREFIX}#{session_id}:*"
        request_keys = @redis.keys(pattern)
        return [] if request_keys.empty?

        # Extract request IDs from the keys
        request_ids = request_keys.map do |key|
          key.sub("#{SESSION_KEY_PREFIX}#{session_id}:", "")
        end

        # Delete all related keys
        all_keys = []
        request_ids.each do |request_id|
          all_keys << "#{REQUEST_KEY_PREFIX}#{request_id}"
        end
        all_keys.concat(request_keys)

        @redis.del(*all_keys) unless all_keys.empty?
        request_ids
      end

      # Get all pending request IDs for a specific session
      #
      # @param session_id [String] the session identifier
      # @return [Array<String>] list of pending request IDs for the session
      def get_session_requests(session_id)
        pattern = "#{SESSION_KEY_PREFIX}#{session_id}:*"
        request_keys = @redis.keys(pattern)

        request_keys.map do |key|
          key.sub("#{SESSION_KEY_PREFIX}#{session_id}:", "")
        end
      end

      # Get all pending request IDs across all sessions
      #
      # @return [Array<String>] list of all pending request IDs
      def get_all_pending_requests
        pattern = "#{REQUEST_KEY_PREFIX}*"
        request_keys = @redis.keys(pattern)

        request_keys.map do |key|
          key.sub(REQUEST_KEY_PREFIX, "")
        end
      end

      # Refresh the TTL for a pending request
      #
      # @param request_id [String] the unique JSON-RPC request identifier
      # @return [Boolean] true if TTL was refreshed, false if request doesn't exist
      def refresh_request_ttl(request_id)
        request_data = @redis.get("#{REQUEST_KEY_PREFIX}#{request_id}")
        return false unless request_data

        @redis.multi do |multi|
          multi.expire("#{REQUEST_KEY_PREFIX}#{request_id}", @ttl)

          begin
            data = JSON.parse(request_data)
            session_id = data["session_id"]
            if session_id
              multi.expire("#{SESSION_KEY_PREFIX}#{session_id}:#{request_id}", @ttl)
            end
          rescue JSON::ParserError
            nil
          end
        end

        true
      end
    end
  end
end
