module ModelContextProtocol
  class Server
    class Router
      ##
      # Maps tool operations to handlers.
      class ToolsMap < BaseMap
        def list(handler, broadcast_changes: false)
          register("tools/list", handler, broadcast_changes:)
        end

        def call(handler)
          register("tools/call", handler)
        end
      end
    end
  end
end
