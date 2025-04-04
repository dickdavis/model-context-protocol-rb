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

    def route(message)
      method = message["method"]
      handler = @handlers[method]
      raise MethodNotFoundError, "Method not found: #{method}" unless handler

      with_environment(@configuration&.environment_variables) do
        handler.call(message)
      end
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
