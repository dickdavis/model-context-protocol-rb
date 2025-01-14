# frozen_string_literal: true

module ModelContextProtocol
  class Server
    class Router
      attr_accessor :server

      def self.new(&block)
        router = allocate
        router.send(:initialize)
        router.instance_eval(&block) if block
        router
      end

      def initialize
        @routes = {}
        register_protocol_routes
      end

      def prompts(&block)
        PromptsMap.new(@routes).instance_eval(&block)
      end

      def resources(&block)
        ResourcesMap.new(@routes).instance_eval(&block)
      end

      def tools(&block)
        ToolsMap.new(@routes).instance_eval(&block)
      end

      def route(message)
        handler_config = @routes[message["method"]]
        return nil unless handler_config

        handler_config[:handler].call(message)
      end

      private

      def server_info
        if server&.configuration
          {
            name: server.configuration.name,
            version: server.configuration.version
          }
        else
          {name: "mcp-server", version: "1.0.0"}
        end
      end

      def register_protocol_routes
        register("initialize") do |_message|
          {
            protocolVersion: ModelContextProtocol::Server::PROTOCOL_VERSION,
            capabilities: build_capabilities,
            serverInfo: server_info
          }
        end

        register("notifications/initialized") do |_message|
          nil # No-op notification handler
        end

        register("ping") do |_message|
          {} # Simple pong response
        end
      end

      def register(method, handler = nil, **options, &block)
        @routes[method] = {
          handler: block || handler,
          options: options
        }
      end

      def build_capabilities
        {
          prompts: has_prompt_routes? ? {broadcast_changes: prompt_broadcasts_changes?} : nil,
          resources: has_resource_routes? ? {
            broadcast_changes: resource_broadcasts_changes?,
            subscribe: resource_allows_subscriptions?
          } : nil,
          tools: has_tool_routes? ? {broadcast_changes: tool_broadcasts_changes?} : nil
        }.compact
      end

      def has_prompt_routes?
        @routes.key?("prompts/list") || @routes.key?("prompts/get")
      end

      def prompt_broadcasts_changes?
        @routes.dig("prompts/list", :options, :broadcast_changes)
      end

      def has_resource_routes?
        @routes.key?("resources/list") || @routes.key?("resources/read")
      end

      def resource_broadcasts_changes?
        @routes.dig("resources/list", :options, :broadcast_changes)
      end

      def resource_allows_subscriptions?
        @routes.dig("resources/read", :options, :allow_subscriptions)
      end

      def has_tool_routes?
        @routes.key?("tools/list") || @routes.key?("tools/call")
      end

      def tool_broadcasts_changes?
        @routes.dig("tools/list", :options, :broadcast_changes)
      end
    end
  end
end
