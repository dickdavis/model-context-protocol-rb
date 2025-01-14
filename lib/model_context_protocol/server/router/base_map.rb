module ModelContextProtocol
  class Server
    class Router
      ##
      # Base class for route maps.
      class BaseMap
        def initialize(routes)
          @routes = routes
        end

        private

        def register(method, handler, **options)
          @routes[method] = {
            handler: handler,
            options: options
          }
        end
      end
    end
  end
end
