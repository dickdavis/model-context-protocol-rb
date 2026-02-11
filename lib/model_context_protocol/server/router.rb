require_relative "cancellable"

module ModelContextProtocol
  class Server::Router
    # Raised when an invalid method is provided.
    class MethodNotFoundError < StandardError; end

    def initialize(configuration:)
      @handlers = {}
      @configuration = configuration
      map_handlers
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
    # @param session_context [Hash] per-request context stored during session initialization
    # @return [Object] the handler result, or nil if cancelled
    def route(message, request_store: nil, session_id: nil, transport: nil, stream_id: nil, session_context: {})
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
        execute_with_context(handler, message, session_context:) do
          context = {
            jsonrpc_request_id:,
            request_store:,
            session_id:,
            progress_token:,
            transport:,
            stream_id:,
            session_context:
          }

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
      map("initialize") do |message|
        client_protocol_version = message["params"]&.dig("protocolVersion")

        negotiated_version = if client_protocol_version && SUPPORTED_PROTOCOL_VERSIONS.include?(client_protocol_version)
          client_protocol_version
        else
          LATEST_PROTOCOL_VERSION
        end

        server_info = {
          name: @configuration.name,
          version: @configuration.version
        }
        server_info[:title] = @configuration.title if @configuration.title

        InitializeResponse[
          protocol_version: negotiated_version,
          capabilities: build_capabilities,
          server_info: server_info,
          instructions: @configuration.instructions
        ]
      end

      map("ping") do
        PingResponse[]
      end

      map("logging/setLevel") do |message|
        level = message["params"]["level"]

        unless Server::ClientLogger::VALID_LOG_LEVELS.include?(level)
          raise Server::ParameterValidationError, "Invalid log level: #{level}. Valid levels are: #{Server::ClientLogger::VALID_LOG_LEVELS.join(", ")}"
        end

        @configuration.client_logger.set_mcp_level(level)
        LoggingSetLevelResponse[]
      end

      map("completion/complete") do |message|
        type = message["params"]["ref"]["type"]

        completion_source = case type
        when "ref/prompt"
          name = message["params"]["ref"]["name"]
          @configuration.registry.find_prompt(name)
        when "ref/resource"
          uri = message["params"]["ref"]["uri"]
          @configuration.registry.find_resource_template(uri)
        else
          raise Server::ParameterValidationError, "ref/type invalid"
        end

        arg_name, arg_value = message["params"]["argument"].values_at("name", "value")

        if completion_source
          completion_source.complete_for(arg_name, arg_value)
        else
          Server::NullCompletion.call(arg_name, arg_value)
        end
      end

      map("resources/list") do |message|
        params = message["params"] || {}

        if @configuration.pagination_enabled? && Server::Pagination.pagination_requested?(params)
          opts = @configuration.pagination_options

          pagination_params = Server::Pagination.extract_pagination_params(
            params,
            default_page_size: opts[:default_page_size],
            max_page_size: opts[:max_page_size]
          )

          @configuration.registry.resources_data(
            cursor: pagination_params[:cursor],
            page_size: pagination_params[:page_size],
            cursor_ttl: opts[:cursor_ttl]
          )
        else
          @configuration.registry.resources_data
        end
      rescue Server::Pagination::InvalidCursorError => e
        raise Server::ParameterValidationError, e.message
      end

      map("resources/read") do |message|
        uri = message["params"]["uri"]
        resource = @configuration.registry.find_resource(uri)
        unless resource
          raise Server::ParameterValidationError, "resource not found for #{uri}"
        end

        resource.call(@configuration.client_logger, @configuration.server_logger, effective_context)
      end

      map("resources/templates/list") do |message|
        params = message["params"] || {}

        if @configuration.pagination_enabled? && Server::Pagination.pagination_requested?(params)
          opts = @configuration.pagination_options

          pagination_params = Server::Pagination.extract_pagination_params(
            params,
            default_page_size: opts[:default_page_size],
            max_page_size: opts[:max_page_size]
          )

          @configuration.registry.resource_templates_data(
            cursor: pagination_params[:cursor],
            page_size: pagination_params[:page_size],
            cursor_ttl: opts[:cursor_ttl]
          )
        else
          @configuration.registry.resource_templates_data
        end
      rescue Server::Pagination::InvalidCursorError => e
        raise Server::ParameterValidationError, e.message
      end

      map("prompts/list") do |message|
        params = message["params"] || {}

        if @configuration.pagination_enabled? && Server::Pagination.pagination_requested?(params)
          opts = @configuration.pagination_options

          pagination_params = Server::Pagination.extract_pagination_params(
            params,
            default_page_size: opts[:default_page_size],
            max_page_size: opts[:max_page_size]
          )

          @configuration.registry.prompts_data(
            cursor: pagination_params[:cursor],
            page_size: pagination_params[:page_size],
            cursor_ttl: opts[:cursor_ttl]
          )
        else
          @configuration.registry.prompts_data
        end
      rescue Server::Pagination::InvalidCursorError => e
        raise Server::ParameterValidationError, e.message
      end

      map("prompts/get") do |message|
        arguments = message["params"]["arguments"]
        symbolized_arguments = arguments.transform_keys(&:to_sym)
        @configuration
          .registry
          .find_prompt(message["params"]["name"])
          .call(symbolized_arguments, @configuration.client_logger, @configuration.server_logger, effective_context)
      end

      map("tools/list") do |message|
        params = message["params"] || {}

        if @configuration.pagination_enabled? && Server::Pagination.pagination_requested?(params)
          opts = @configuration.pagination_options

          pagination_params = Server::Pagination.extract_pagination_params(
            params,
            default_page_size: opts[:default_page_size],
            max_page_size: opts[:max_page_size]
          )

          @configuration.registry.tools_data(
            cursor: pagination_params[:cursor],
            page_size: pagination_params[:page_size],
            cursor_ttl: opts[:cursor_ttl]
          )
        else
          @configuration.registry.tools_data
        end
      rescue Server::Pagination::InvalidCursorError => e
        raise Server::ParameterValidationError, e.message
      end

      map("tools/call") do |message|
        arguments = message["params"]["arguments"]
        symbolized_arguments = arguments.transform_keys(&:to_sym)
        @configuration
          .registry
          .find_tool(message["params"]["name"])
          .call(symbolized_arguments, @configuration.client_logger, @configuration.server_logger, effective_context)
      end
    end

    # Merge server-level context with per-request session_context
    # Session context takes precedence over server context
    def effective_context
      session_context = Thread.current[:mcp_context]&.dig(:session_context) || {}
      (@configuration.context || {}).merge(session_context)
    end

    def build_capabilities
      {}.tap do |capabilities|
        capabilities[:completions] = {}
        capabilities[:logging] = {}

        registry = @configuration.registry
        supports_list_changed = @configuration.transport_type == :streamable_http

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

    # Execute handler with appropriate context setup
    def execute_with_context(handler, message, session_context:, &block)
      # Skip ENV manipulation for streamable_http transport because ENV is
      # global state and modifying it is thread-unsafe in multi-threaded servers.
      # For stdio transport, apply ENV variables as before (single-threaded).
      if @configuration.transport_type == :streamable_http
        yield
      else
        with_environment(@configuration.environment_variables, &block)
      end
    end

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
