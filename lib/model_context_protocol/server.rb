module ModelContextProtocol
  class Server
    # Raised when invalid response arguments are provided.
    class ResponseArgumentsError < StandardError; end

    # Raised when invalid parameters are provided.
    class ParameterValidationError < StandardError; end

    attr_reader :configuration, :router, :transport

    def initialize
      @configuration = Configuration.new
      yield(@configuration) if block_given?
      @router = Router.new(configuration:)
    end

    # Start the server for stdio transport
    # For HTTP transport, use Server.setup and Server.serve instead
    def start
      configuration.validate!

      case configuration.transport_type
      when :stdio, nil
        @transport = StdioTransport.new(router: @router, configuration: @configuration)
        @transport.handle
      when :streamable_http
        raise ArgumentError,
          "Use Server.setup and Server.serve for streamable_http transport. " \
          "Example: Server.setup { |c| ... } then Server.serve(env: request.env)"
      else
        raise ArgumentError, "Unknown transport: #{configuration.transport_type}"
      end
    end

    class << self
      attr_reader :singleton_transport, :singleton_configuration, :singleton_router

      def configure_redis(&block)
        ModelContextProtocol::Server::RedisConfig.configure(&block)
      end

      def configure_server_logging(&block)
        ModelContextProtocol::Server::GlobalConfig::ServerLogging.configure(&block)
      end

      # Configure the singleton server without starting background threads.
      # This is safe to call before forking (e.g., in Rails initializers or Puma master process).
      # Call Server.start after forking to create the transport and start background threads.
      #
      # @param configuration [Configuration, nil] Pre-built configuration object
      # @yield [Configuration] Block to configure the server
      # @raise [RuntimeError] If server is already configured
      # @raise [ArgumentError] If neither configuration nor block provided
      def setup(configuration = nil)
        raise "Server already configured. Call Server.shutdown first." if @singleton_configuration

        @singleton_configuration = if configuration
          configuration
        elsif block_given?
          config = Configuration.new
          yield(config)
          config
        else
          raise ArgumentError, "Configuration or block required"
        end

        @singleton_configuration.validate!
        @singleton_router = Router.new(configuration: @singleton_configuration)
      end

      # Start the singleton transport and background threads.
      # Must be called after Server.setup. In Puma clustered mode, call this
      # after forking (e.g., in on_worker_boot hook).
      #
      # @raise [RuntimeError] If server not configured
      # @raise [RuntimeError] If server already running
      def start
        raise "Server not configured. Call Server.setup first." unless @singleton_configuration
        raise "Server already running. Call Server.shutdown first." if @singleton_transport

        @singleton_transport = StreamableHttpTransport.new(
          router: @singleton_router,
          configuration: @singleton_configuration
        )
      end

      # Handle an incoming HTTP request using the singleton transport
      #
      # @param env [Hash] Rack environment hash
      # @param session_context [Hash] Per-request context (e.g., user_id from auth)
      # @return [Hash] Response hash with :json, :status, :headers keys
      # @raise [RuntimeError] If server not running
      def serve(env:, session_context: {})
        raise "Server not running. Call Server.start first." unless @singleton_transport

        @singleton_transport.handle(env: env, session_context: session_context)
      end

      # Gracefully shutdown the singleton transport
      # Stops background threads and cleans up resources
      def shutdown
        @singleton_transport&.shutdown
        @singleton_transport = nil
        @singleton_router = nil
        @singleton_configuration = nil
      end

      # Check if singleton server is configured (setup has been called)
      #
      # @return [Boolean] true if setup has been called
      def configured?
        !@singleton_configuration.nil?
      end

      # Check if singleton transport is running (start has been called)
      #
      # @return [Boolean] true if start has been called and transport is active
      def running?
        !@singleton_transport.nil?
      end

      # Reset singleton state (for testing)
      # This is an alias for shutdown
      def reset!
        shutdown
      end
    end
  end
end
