module ModelContextProtocol
  class Server
    class Router
      ##
      # Maps resource operations to handlers.
      class ResourcesMap < BaseMap
        def list(handler, broadcast_changes: false)
          register("resources/list", handler, broadcast_changes:)
        end

        def read(handler, allow_subscriptions: false)
          register("resources/read", handler, allow_subscriptions:)
        end
      end
    end
  end
end
