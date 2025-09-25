module ModelContextProtocol
  class Server
    module Instrumentation
      Event = Data.define(:method, :request_id, :metrics) do
        def initialize(method:, request_id:, metrics: {})
          super
        end

        def serialized
          {method:, request_id:, metrics:}
        end
      end
    end
  end
end
