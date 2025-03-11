module ModelContextProtocol
  class Server::Router
    # Raised when an invalid method is provided.
    class MethodNotFoundError < StandardError; end

    def initialize
      @handlers = {}
    end

    def map(method, &handler)
      @handlers[method] = handler
    end

    def route(message)
      method = message["method"]
      handler = @handlers[method]
      raise MethodNotFoundError, "Method not found: #{method}" unless handler

      handler.call(message)
    end
  end
end
