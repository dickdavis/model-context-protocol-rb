require "logger"

module ModelContextProtocol
  class Server
    # Raised when invalid response arguments are provided.
    class ResponseArgumentsError < StandardError; end

    # Raised when invalid parameters are provided.
    class ParameterValidationError < StandardError; end

    attr_reader :configuration, :router

    def initialize
      @configuration = Configuration.new
      yield(@configuration) if block_given?
      @router = Router.new(configuration:)
      map_handlers
    end

    def start
      configuration.validate!
      logdev = configuration.logging_enabled? ? $stderr : File::NULL
      StdioTransport.new(logger: Logger.new(logdev), router:).begin
    end

    private

    PROTOCOL_VERSION = "2024-11-05".freeze
    private_constant :PROTOCOL_VERSION

    InitializeResponse = Data.define(:protocol_version, :capabilities, :server_info) do
      def serialized
        {
          protocolVersion: protocol_version,
          capabilities: capabilities,
          serverInfo: server_info
        }
      end
    end

    PingResponse = Data.define do
      def serialized
        {}
      end
    end

    def map_handlers
      router.map("initialize") do |_message|
        InitializeResponse[
          protocol_version: PROTOCOL_VERSION,
          capabilities: build_capabilities,
          server_info: {
            name: configuration.name,
            version: configuration.version
          }
        ]
      end

      router.map("ping") do
        PingResponse[]
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

      router.map("resources/list") do
        configuration.registry.resources_data
      end

      router.map("resources/read") do |message|
        uri = message["params"]["uri"]
        resource = configuration.registry.find_resource(uri)
        unless resource
          raise ModelContextProtocol::Server::ParameterValidationError, "resource not found for #{uri}"
        end

        resource.call(configuration.context)
      end

      router.map("resources/templates/list") do |message|
        configuration.registry.resource_templates_data
      end

      router.map("prompts/list") do
        configuration.registry.prompts_data
      end

      router.map("prompts/get") do |message|
        configuration
          .registry
          .find_prompt(message["params"]["name"])
          .call(message["params"]["arguments"], configuration.context)
      end

      router.map("tools/list") do
        configuration.registry.tools_data
      end

      router.map("tools/call") do |message|
        configuration
          .registry
          .find_tool(message["params"]["name"])
          .call(message["params"]["arguments"], configuration.context)
      end
    end

    def build_capabilities
      {}.tap do |capabilities|
        capabilities[:completions] = {}
        capabilities[:logging] = {} if configuration.logging_enabled?

        registry = configuration.registry

        if registry.prompts_options.any? && !registry.instance_variable_get(:@prompts).empty?
          capabilities[:prompts] = {
            listChanged: registry.prompts_options[:list_changed]
          }.except(:completions).compact
        end

        if registry.resources_options.any? && !registry.instance_variable_get(:@resources).empty?
          capabilities[:resources] = {
            subscribe: registry.resources_options[:subscribe],
            listChanged: registry.resources_options[:list_changed]
          }.compact
        end

        if registry.tools_options.any? && !registry.instance_variable_get(:@tools).empty?
          capabilities[:tools] = {
            listChanged: registry.tools_options[:list_changed]
          }.compact
        end
      end
    end
  end
end
