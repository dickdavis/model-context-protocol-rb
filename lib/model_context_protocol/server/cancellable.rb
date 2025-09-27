require "concurrent-ruby"

module ModelContextProtocol
  module Server::Cancellable
    # Raised when a request has been cancelled by the client
    class CancellationError < StandardError; end

    # Execute a block with automatic cancellation support for blocking I/O operations.
    # This method uses Concurrent::TimerTask to poll for cancellation every 100ms
    # and can interrupt even blocking operations like HTTP requests or database queries.
    #
    # @param interval [Float] polling interval in seconds (default: 0.1)
    # @yield block to execute with cancellation support
    # @return [Object] the result of the block
    # @raise [CancellationError] if the request is cancelled during execution
    #
    # @example
    #   cancellable do
    #     response = Net::HTTP.get(URI('https://slow-api.example.com'))
    #     process_response(response)
    #   end
    def cancellable(interval: 0.1, &block)
      context = Thread.current[:mcp_context]
      executing_thread = Concurrent::AtomicReference.new(nil)

      timer_task = Concurrent::TimerTask.new(execution_interval: interval) do
        if context && context[:request_store] && context[:jsonrpc_request_id]
          if context[:request_store].cancelled?(context[:jsonrpc_request_id])
            thread = executing_thread.get
            thread&.raise(CancellationError, "Request was cancelled") if thread&.alive?
          end
        end
      end

      begin
        executing_thread.set(Thread.current)

        if context && context[:request_store] && context[:jsonrpc_request_id]
          if context[:request_store].cancelled?(context[:jsonrpc_request_id])
            raise CancellationError, "Request #{context[:jsonrpc_request_id]} was cancelled"
          end
        end

        timer_task.execute

        result = block.call
        result
      ensure
        executing_thread.set(nil)
        timer_task&.shutdown if timer_task&.running?
      end
    end
  end
end
