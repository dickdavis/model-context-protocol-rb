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
      map_handlers
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

    private

    SUPPORTED_PROTOCOL_VERSIONS = ["2025-06-18"].freeze
    private_constant :SUPPORTED_PROTOCOL_VERSIONS

    LATEST_PROTOCOL_VERSION = SUPPORTED_PROTOCOL_VERSIONS.first
    private_constant :LATEST_PROTOCOL_VERSION

    InitializeResponse = Data.define(:protocol_version, :capabilities, :server_info, :instructions) do
      def serialized
        response = {
          protocolVersion: protocol_version,
          capabilities: capabilities,
          serverInfo: server_info
        }
        response[:instructions] = instructions if instructions
        response
      end
    end

    PingResponse = Data.define do
      def serialized
        {}
      end
    end

    LoggingSetLevelResponse = Data.define do
      def serialized
        {}
      end
    end

    def map_handlers
      router.map("initialize") do |message|
        client_protocol_version = message["params"]&.dig("protocolVersion")

        negotiated_version = if client_protocol_version && SUPPORTED_PROTOCOL_VERSIONS.include?(client_protocol_version)
          client_protocol_version
        else
          LATEST_PROTOCOL_VERSION
        end

        server_info = {
          name: configuration.name,
          version: configuration.version
        }
        server_info[:title] = configuration.title if configuration.title

        InitializeResponse[
          protocol_version: negotiated_version,
          capabilities: build_capabilities,
          server_info: server_info,
          instructions: configuration.instructions
        ]
      end

      router.map("ping") do
        PingResponse[]
      end

      router.map("logging/setLevel") do |message|
        level = message["params"]["level"]

        unless ClientLogger::VALID_LOG_LEVELS.include?(level)
          raise ParameterValidationError, "Invalid log level: #{level}. Valid levels are: #{ClientLogger::VALID_LOG_LEVELS.join(", ")}"
        end

        configuration.client_logger.set_mcp_level(level)
        LoggingSetLevelResponse[]
      end

      router.map("completion/complete") do |message|
        type = message["params"]["ref"]["type"]

        completion_source = case type
        when "ref/prompt"
          name = message["params"]["ref"]["name"]
          configuration.registry.find_prompt(name)
        when "ref/resource"
          uri = message["params"]["ref"]["uri"]
          configuration.registry.find_resource_template(uri)
        else
          raise ModelContextProtocol::Server::ParameterValidationError, "ref/type invalid"
        end

        arg_name, arg_value = message["params"]["argument"].values_at("name", "value")

        if completion_source
          completion_source.complete_for(arg_name, arg_value)
        else
          ModelContextProtocol::Server::NullCompletion.call(arg_name, arg_value)
        end
      end

      router.map("resources/list") do |message|
        params = message["params"] || {}

        if configuration.pagination_enabled? && Server::Pagination.pagination_requested?(params)
          opts = configuration.pagination_options

          pagination_params = Server::Pagination.extract_pagination_params(
            params,
            default_page_size: opts[:default_page_size],
            max_page_size: opts[:max_page_size]
          )

          configuration.registry.resources_data(
            cursor: pagination_params[:cursor],
            page_size: pagination_params[:page_size],
            cursor_ttl: opts[:cursor_ttl]
          )
        else
          configuration.registry.resources_data
        end
      rescue Server::Pagination::InvalidCursorError => e
        raise ParameterValidationError, e.message
      end

      router.map("resources/read") do |message|
        uri = message["params"]["uri"]
        resource = configuration.registry.find_resource(uri)
        unless resource
          raise ModelContextProtocol::Server::ParameterValidationError, "resource not found for #{uri}"
        end

        resource.call(configuration.client_logger, configuration.server_logger, effective_context)
      end

      router.map("resources/templates/list") do |message|
        params = message["params"] || {}

        if configuration.pagination_enabled? && Server::Pagination.pagination_requested?(params)
          opts = configuration.pagination_options

          pagination_params = Server::Pagination.extract_pagination_params(
            params,
            default_page_size: opts[:default_page_size],
            max_page_size: opts[:max_page_size]
          )

          configuration.registry.resource_templates_data(
            cursor: pagination_params[:cursor],
            page_size: pagination_params[:page_size],
            cursor_ttl: opts[:cursor_ttl]
          )
        else
          configuration.registry.resource_templates_data
        end
      rescue Server::Pagination::InvalidCursorError => e
        raise ParameterValidationError, e.message
      end

      router.map("prompts/list") do |message|
        params = message["params"] || {}

        if configuration.pagination_enabled? && Server::Pagination.pagination_requested?(params)
          opts = configuration.pagination_options

          pagination_params = Server::Pagination.extract_pagination_params(
            params,
            default_page_size: opts[:default_page_size],
            max_page_size: opts[:max_page_size]
          )

          configuration.registry.prompts_data(
            cursor: pagination_params[:cursor],
            page_size: pagination_params[:page_size],
            cursor_ttl: opts[:cursor_ttl]
          )
        else
          configuration.registry.prompts_data
        end
      rescue Server::Pagination::InvalidCursorError => e
        raise ParameterValidationError, e.message
      end

      router.map("prompts/get") do |message|
        arguments = message["params"]["arguments"]
        symbolized_arguments = arguments.transform_keys(&:to_sym)
        configuration
          .registry
          .find_prompt(message["params"]["name"])
          .call(symbolized_arguments, configuration.client_logger, configuration.server_logger, effective_context)
      end

      router.map("tools/list") do |message|
        params = message["params"] || {}

        if configuration.pagination_enabled? && Server::Pagination.pagination_requested?(params)
          opts = configuration.pagination_options

          pagination_params = Server::Pagination.extract_pagination_params(
            params,
            default_page_size: opts[:default_page_size],
            max_page_size: opts[:max_page_size]
          )

          configuration.registry.tools_data(
            cursor: pagination_params[:cursor],
            page_size: pagination_params[:page_size],
            cursor_ttl: opts[:cursor_ttl]
          )
        else
          configuration.registry.tools_data
        end
      rescue Server::Pagination::InvalidCursorError => e
        raise ParameterValidationError, e.message
      end

      router.map("tools/call") do |message|
        arguments = message["params"]["arguments"]
        symbolized_arguments = arguments.transform_keys(&:to_sym)
        configuration
          .registry
          .find_tool(message["params"]["name"])
          .call(symbolized_arguments, configuration.client_logger, configuration.server_logger, effective_context)
      end
    end

    # Merge server-level context with per-request session_context
    # Session context takes precedence over server context
    def effective_context
      session_context = Thread.current[:mcp_context]&.dig(:session_context) || {}
      (configuration.context || {}).merge(session_context)
    end

    def build_capabilities
      {}.tap do |capabilities|
        capabilities[:completions] = {}
        capabilities[:logging] = {}

        registry = configuration.registry
        supports_list_changed = configuration.transport_type == :streamable_http

        if !registry.instance_variable_get(:@prompts).empty?
          prompts_caps = {}
          prompts_caps[:listChanged] = true if supports_list_changed
          capabilities[:prompts] = prompts_caps
        end

        if !registry.instance_variable_get(:@resources).empty?
          resources_caps = {}
          resources_caps[:subscribe] = true if registry.resources_options[:subscribe]
          resources_caps[:listChanged] = true if supports_list_changed
          capabilities[:resources] = resources_caps
        end

        if !registry.instance_variable_get(:@tools).empty?
          tools_caps = {}
          tools_caps[:listChanged] = true if supports_list_changed
          capabilities[:tools] = tools_caps
        end
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

      # Initialize a singleton transport for handling multiple requests
      # This is the recommended pattern for production HTTP deployments
      # where you want only 2 background threads (MessagePoller, StreamMonitor)
      # regardless of concurrent connections.
      #
      # @param configuration [Configuration, nil] Pre-built configuration object
      # @yield [Configuration] Block to configure the server
      # @raise [RuntimeError] If server is already initialized
      # @raise [ArgumentError] If neither configuration nor block provided
      def setup(configuration = nil)
        raise "Server already initialized. Call Server.shutdown first." if @singleton_transport

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

        # Map handlers using an instance to access private map_handlers method
        server_instance = allocate
        server_instance.instance_variable_set(:@configuration, @singleton_configuration)
        server_instance.instance_variable_set(:@router, @singleton_router)
        server_instance.send(:map_handlers)

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
      # @raise [RuntimeError] If server not initialized
      def serve(env:, session_context: {})
        raise "Server not initialized. Call Server.setup first." unless @singleton_transport

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

      # Check if singleton transport is configured and ready
      #
      # @return [Boolean] true if setup has been called and transport is ready
      def singleton_configured?
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
