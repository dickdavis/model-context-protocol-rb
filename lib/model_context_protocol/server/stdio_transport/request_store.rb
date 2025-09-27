module ModelContextProtocol
  class Server::StdioTransport
    # Thread-safe in-memory storage for tracking active requests and their cancellation status.
    # This store is used by StdioTransport to manage request lifecycle and handle cancellation.
    class RequestStore
      def initialize
        @mutex = Mutex.new
        @requests = {}
      end

      # Register a new request with its associated thread
      #
      # @param jsonrpc_request_id [String] the unique JSON-RPC request identifier
      # @param thread [Thread] the thread processing this request (defaults to current thread)
      # @return [void]
      def register_request(jsonrpc_request_id, thread = Thread.current)
        @mutex.synchronize do
          @requests[jsonrpc_request_id] = {
            thread:,
            cancelled: false,
            started_at: Time.now
          }
        end
      end

      # Mark a request as cancelled
      #
      # @param jsonrpc_request_id [String] the unique JSON-RPC request identifier
      # @return [Boolean] true if request was found and marked cancelled, false otherwise
      def mark_cancelled(jsonrpc_request_id)
        @mutex.synchronize do
          if (request = @requests[jsonrpc_request_id])
            request[:cancelled] = true
            return true
          end
          false
        end
      end

      # Check if a request has been cancelled
      #
      # @param jsonrpc_request_id [String] the unique JSON-RPC request identifier
      # @return [Boolean] true if the request is cancelled, false otherwise
      def cancelled?(jsonrpc_request_id)
        @mutex.synchronize do
          @requests[jsonrpc_request_id]&.fetch(:cancelled, false) || false
        end
      end

      # Unregister a request (typically called when request completes)
      #
      # @param jsonrpc_request_id [String] the unique JSON-RPC request identifier
      # @return [Hash, nil] the removed request data, or nil if not found
      def unregister_request(jsonrpc_request_id)
        @mutex.synchronize do
          @requests.delete(jsonrpc_request_id)
        end
      end

      # Get information about a specific request
      #
      # @param jsonrpc_request_id [String] the unique JSON-RPC request identifier
      # @return [Hash, nil] request information or nil if not found
      def get_request(jsonrpc_request_id)
        @mutex.synchronize do
          @requests[jsonrpc_request_id]&.dup
        end
      end

      # Get all active request IDs
      #
      # @return [Array<String>] list of active request IDs
      def active_requests
        @mutex.synchronize do
          @requests.keys.dup
        end
      end

      # Clean up old requests (useful for preventing memory leaks)
      #
      # @param max_age_seconds [Integer] maximum age of requests to keep
      # @return [Array<String>] list of cleaned up request IDs
      def cleanup_old_requests(max_age_seconds = 300)
        cutoff_time = Time.now - max_age_seconds
        removed_ids = []

        @mutex.synchronize do
          @requests.delete_if do |jsonrpc_request_id, data|
            if data[:started_at] < cutoff_time
              removed_ids << jsonrpc_request_id
              true
            else
              false
            end
          end
        end

        removed_ids
      end
    end
  end
end
