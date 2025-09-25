module ModelContextProtocol
  class Server
    module Instrumentation
      class BaseCollector
        def before_request(context)
          # Override in subclasses
        end

        def after_request(context, result)
          # Override in subclasses
        end

        def collect_metrics(context)
          # Override in subclasses to return a hash of metrics
          {}
        end
      end
    end
  end
end
