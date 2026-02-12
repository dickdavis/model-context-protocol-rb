module ModelContextProtocol
  class Server
    # Raised when invalid response arguments are provided.
    class ResponseArgumentsError < StandardError; end

    # Raised when invalid parameters are provided.
    class ParameterValidationError < StandardError; end

    # Raised by class-level start and serve when no server instance has been configured
    # via with_stdio_transport or with_streamable_http_transport.
    class NotConfiguredError < StandardError; end

    # @return [Configuration] the transport-specific configuration (StdioConfiguration or StreamableHttpConfiguration)
    # @return [Router] the message router that dispatches JSON-RPC methods to handlers
    # @return [Transport, nil] the active transport (StdioTransport or StreamableHttpTransport), or nil if not started
    attr_reader :configuration, :router, :transport

    # Activate the transport layer to begin processing MCP protocol messages.
    # For stdio: blocks the calling thread while handling stdin/stdout communication.
    # For HTTP: spawns background threads for Redis polling and stream monitoring, then returns immediately.
    #
    # @raise [RuntimeError] if transport is already running (prevents double-initialization)
    # @return [void]
    def start
      raise "Server already running. Call shutdown first." if @transport

      case configuration.transport_type
      when :stdio
        @transport = StdioTransport.new(router: @router, configuration: @configuration)
        @transport.handle
      when :streamable_http
        @transport = StreamableHttpTransport.new(router: @router, configuration: @configuration)
      end
    end

    # Handle a single HTTP request through the streamable HTTP transport.
    # Rack applications delegate each incoming request to this method.
    #
    # @param env [Hash] the Rack environment hash containing request details
    # @param session_context [Hash] per-session data (e.g., user_id) stored during initialization
    # @raise [RuntimeError] if transport hasn't been started via start
    # @raise [RuntimeError] if called on stdio transport (HTTP-only method)
    # @return [Hash] Rack response with :status, :headers, and either :json or :stream/:stream_proc
    def serve(env:, session_context: {})
      raise "Server not running. Call start first." unless @transport
      raise "serve is only available for streamable_http transport" unless configuration.transport_type == :streamable_http

      @transport.handle(env: env, session_context: session_context)
    end

    # Tear down the transport and release resources.
    # For stdio: no-ops (StdioTransport doesn't implement shutdown).
    # For HTTP: stops background threads and closes active SSE streams.
    #
    # @return [void]
    def shutdown
      @transport.shutdown if @transport.respond_to?(:shutdown)
      @transport = nil
    end

    # Query whether the server has been configured with a transport type.
    # The Puma plugin checks this before attempting to start the server.
    #
    # @return [Boolean] true if with_stdio_transport or with_streamable_http_transport has been called
    def configured?
      !@configuration.nil?
    end

    # Query whether the server's transport layer is actively processing messages.
    # The Puma plugin checks this to avoid redundant start calls and to guard shutdown.
    #
    # @return [Boolean] true if start has been called and transport is initialized
    def running?
      !@transport.nil?
    end

    class << self
      # @return [Server, nil] the singleton server instance created by with_stdio_transport or with_streamable_http_transport
      attr_accessor :instance

      # Factory method for creating a server with standard input/output transport.
      # For standalone scripts that communicate over stdin/stdout (e.g., Claude Desktop integration).
      # Yields a StdioConfiguration for setting name, version, registry, and environment variables.
      #
      # @yieldparam config [StdioConfiguration] the configuration to populate
      # @return [Server] the configured server instance (also stored in Server.instance)
      # @example
      #   server = ModelContextProtocol::Server.with_stdio_transport do |config|
      #     config.name = "My MCP Server"
      #     config.registry { tools { register MyTool } }
      #   end
      #   server.start  # blocks while handling stdio
      def with_stdio_transport(&block)
        build_server(StdioConfiguration.new, &block)
      end

      # Factory method for creating a server with streamable HTTP transport.
      # For Rack applications that serve multiple clients over HTTP with Redis-backed session coordination.
      # Yields a StreamableHttpConfiguration for setting name, version, registry, session requirements, and CORS.
      #
      # @yieldparam config [StreamableHttpConfiguration] the configuration to populate
      # @return [Server] the configured server instance (also stored in Server.instance)
      # @raise [InvalidTransportError] if redis_url is not set or invalid
      # @example
      #   server = ModelContextProtocol::Server.with_streamable_http_transport do |config|
      #     config.name = "My HTTP MCP Server"
      #     config.redis_url = ENV.fetch("REDIS_URL")
      #     config.require_sessions = true
      #     config.allowed_origins = ["*"]
      #   end
      #   server.start  # spawns background threads, returns immediately
      def with_streamable_http_transport(&block)
        build_server(StreamableHttpConfiguration.new, &block)
      end

      # Configure global server-side logging (distinct from client-facing logs sent via JSON-RPC).
      # Applies to all server instances; typically called once per application.
      # For stdio transport, logdev must not be $stdout (would corrupt protocol messages).
      #
      # @yieldparam config [GlobalConfig::ServerLogging] the logging configuration
      # @return [void]
      # @example
      #   ModelContextProtocol::Server.configure_server_logging do |logger|
      #     logger.level = Logger::DEBUG
      #     logger.logdev = $stderr  # or a file for stdio transport
      #   end
      def configure_server_logging(&block)
        Server::GlobalConfig::ServerLogging.configure(&block)
      end

      # Class-level delegations that forward to the singleton instance.
      # Provided as a convenience for web server integrations (e.g., the Puma plugin in
      # lib/puma/plugin/mcp.rb) that manage the server lifecycle through hooks rather
      # than holding a direct reference to the server instance.

      # Query whether any server instance has been configured.
      # Returns false when no instance exists — the server genuinely isn't configured yet,
      # so callers can use this as a guard before calling start.
      #
      # @return [Boolean] true if with_stdio_transport or with_streamable_http_transport has been called
      def configured?
        instance&.configured? || false
      end

      # Query whether any server instance is actively processing messages.
      # Returns false when no instance exists, allowing callers to guard both
      # start (to avoid redundant starts) and shutdown (to skip if not running).
      #
      # @return [Boolean] true if a server instance exists and its transport is initialized
      def running?
        instance&.running? || false
      end

      # Activate the transport layer to begin processing MCP protocol messages.
      # Raises when no instance exists because a caller who forgot to invoke a factory method
      # would otherwise get silent nil. Web server integrations like the Puma plugin guard
      # with configured? first, but direct callers need the error.
      #
      # @raise [NotConfiguredError] if with_stdio_transport or with_streamable_http_transport hasn't been called
      # @return [void]
      def start
        raise NotConfiguredError, "Server not configured. Call with_stdio_transport or with_streamable_http_transport first." unless instance
        instance.start
      end

      # Handle a single HTTP request by forwarding to the instance's serve method.
      # Used by Rails/Sinatra/Rack controllers as an alternative to calling Server.instance.serve directly.
      # Raises when no instance exists for the same reason as start — a controller receiving
      # requests without a configured server is always a misconfiguration.
      #
      # @param env [Hash] the Rack environment hash containing request details
      # @param session_context [Hash] per-session data (e.g., user_id) stored during initialization
      # @raise [NotConfiguredError] if with_streamable_http_transport hasn't been called
      # @return [Hash] Rack response with :status, :headers, and either :json or :stream/:stream_proc
      def serve(env:, session_context: {})
        raise NotConfiguredError, "Server not configured. Call with_streamable_http_transport first." unless instance
        instance.serve(env: env, session_context: session_context)
      end

      # Tear down the transport and release resources if a server is running.
      # Safe-navigates when no instance exists because callers in cleanup paths
      # (signal handlers, web server shutdown hooks, test teardown) need this to
      # work unconditionally.
      #
      # @return [void]
      def shutdown
        instance&.shutdown
      end

      # Tear down the transport and clear the singleton instance to allow reconfiguration.
      # Safe-navigates when no instance exists because test teardown (before/after hooks)
      # must succeed even when a test fails before the server is initialized.
      #
      # @return [void]
      def reset!
        instance&.shutdown
        self.instance = nil
      end

      private

      # Internal factory logic shared by with_stdio_transport and with_streamable_http_transport.
      # Validates configuration, creates a server instance without calling initialize (via allocate),
      # initializes it with the configuration, and stores it in the singleton.
      #
      # @param config [Configuration] the transport-specific configuration subclass
      # @yieldparam config [Configuration] if a block is given, yields for additional setup
      # @return [Server] the configured and stored server instance
      def build_server(config)
        yield(config) if block_given?
        config.validate!
        config.send(:setup_transport!)
        server = allocate
        server.send(:initialize_from_configuration, config)
        self.instance = server
        server
      end
    end

    private

    # Internal initializer called by build_server after allocate.
    # Bypasses the standard initialize to allow configuration-driven construction.
    # Creates the Router that maps JSON-RPC methods to handlers based on the registry.
    #
    # @param configuration [Configuration] the validated transport-specific configuration
    # @return [void]
    def initialize_from_configuration(configuration)
      @configuration = configuration
      @router = Router.new(configuration:)
    end
  end
end
