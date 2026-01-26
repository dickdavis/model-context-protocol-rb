require_relative "cancellable"

module ModelContextProtocol
  class Server::Router
    # Raised when an invalid method is provided.
    class MethodNotFoundError < StandardError; end

    def initialize(configuration: nil)
      @handlers = {}
      @configuration = configuration
    end

    def map(method, &handler)
      @handlers[method] = handler
    end

    # Route a message to its handler with request tracking support
    #
    # @param message [Hash] the JSON-RPC message
    # @param request_store [Object] the request store for tracking cancellation
    # @param session_id [String, nil] the session ID for HTTP transport
    # @param transport [Object, nil] the transport for sending notifications
    # @param stream_id [String, nil] the specific stream ID for targeted notifications
    # @return [Object] the handler result, or nil if cancelled
    def route(message, request_store: nil, session_id: nil, transport: nil, stream_id: nil)
      method = message["method"]
      handler = @handlers[method]
      raise MethodNotFoundError, "Method not found: #{method}" unless handler

      jsonrpc_request_id = message["id"]
      progress_token = message.dig("params", "_meta", "progressToken")

      if jsonrpc_request_id && request_store
        request_store.register_request(jsonrpc_request_id, session_id)
      end

      result = nil
      begin
        with_environment(@configuration&.environment_variables) do
          context = {jsonrpc_request_id:, request_store:, session_id:, progress_token:, transport:, stream_id:}

          Thread.current[:mcp_context] = context

          result = handler.call(message)
        end
      rescue Server::Cancellable::CancellationError
        return nil
      ensure
        if jsonrpc_request_id && request_store
          request_store.unregister_request(jsonrpc_request_id)
        end

        Thread.current[:mcp_context] = nil
      end

      result
    end

    private

    def with_environment(vars)
      original = ENV.to_h
      vars&.each { |key, value| ENV[key] = value }
      yield
    ensure
      ENV.clear
      original.each { |key, value| ENV[key] = value }
    end
  end
end
