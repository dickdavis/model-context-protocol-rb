require "json"

module ModelContextProtocol
  class Server
    # Raised when invalid parameters are provided.
    class ParameterValidationError < StandardError; end

    class Configuration
      attr_accessor :enable_log, :name, :registry, :version

      def logging_enabled?
        enable_log || false
      end

      def validate!
        raise InvalidServerNameError unless valid_name?
        raise InvalidServerVersionError unless valid_version?
      end

      private

      def valid_name?
        true
      end

      def valid_version?
        true
      end
    end

    PROTOCOL_VERSION = "2024-11-05".freeze

    attr_reader :configuration

    def initialize
      @configuration = Configuration.new
      yield(@configuration) if block_given?
    end

    def start
      log("Server starting")

      configuration.validate!

      loop do
        begin
          line = $stdin.gets
          break unless line

          message = JSON.parse(line.chomp)
          log("Received message: #{message.inspect}")

          if message["method"] == "initialize"
            send_response(message["id"], protocol_initialization_info)
          end

          if message["method"] == "notifications/initialized"
            next
          end

          if message["method"] == "ping"
            send_response(message["id"], {})
            next
          end

          if message["method"] == "prompts/list"
            send_response(message["id"], configuration.registry.serialized_prompts)
            next
          end

          if message["method"] == "resources/list"
            send_response(message["id"], configuration.registry.serialized_resources)
            next
          end

          if message["method"] == "tools/list"
            send_response(message["id"], configuration.registry.serialized_tools)
            next
          end

          response = case message["method"]
                     when "prompts/get"
                       configuration.registry.find_prompt(message["params"]["name"]).call(message["params"]["arguments"])
                     when "resources/read"
                       configuration.registry.find_resource(message["params"]["uri"]).call
                     when "tools/call"
                       configuration.registry.find_tool(message["params"]["name"]).call(message["params"]["arguments"])
                     end

          send_response(message["id"], response) if response
        end
      rescue ModelContextProtocol::Server::ParameterValidationError => error
        send_error_response(message["id"], {code: -32602, message: error.message})
      rescue => e
        log("Error: #{e.message}")
        log(e.backtrace)
      end
    end

    private

    def log(output)
      warn(output) if configuration.logging_enabled?
    end

    def send_response(id, result)
      response = {jsonrpc: "2.0", id:, result:}
      $stdout.puts(JSON.generate(response))
      $stdout.flush
    end

    def send_error_response(id, error)
      response = {jsonrpc: "2.0", id:, error:}
      $stdout.puts(JSON.generate(response))
      $stdout.flush
    end

    def protocol_initialization_info
      capabilities = {}
      capabilities[:logging] = {} if configuration.logging_enabled?

      registry = configuration.registry

      if registry.prompts_options.any? && !registry.instance_variable_get(:@prompts).empty?
        capabilities[:prompts] = {
          listChanged: registry.prompts_options[:list_changed]
        }.compact
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

      {
        protocolVersion: "2024-11-05",
        capabilities: capabilities,
        serverInfo: {
          name: configuration.name,
          version: configuration.version
        }
      }
    end
  end
end
