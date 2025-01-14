module ModelContextProtocol
  class Server
    class Router
      ##
      # Maps prompt operations to handlers.
      class PromptsMap < BaseMap
        def list(handler, broadcast_changes: false)
          register("prompts/list", handler, broadcast_changes:)
        end

        def get(handler)
          register("prompts/get", handler)
        end
      end
    end
  end
end
