require_relative "base_collector"

module ModelContextProtocol
  class Server
    module Instrumentation
      class TimingCollector < BaseCollector
        def before_request(context)
          context[:timing_start] = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)
        end

        def after_request(context, result)
          context[:timing_end] = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)
        end

        def collect_metrics(context)
          return {} unless context[:timing_start] && context[:timing_end]

          {
            cpu_time_ms: ((context[:timing_end] - context[:timing_start]) * 1000).round(2)
          }
        end
      end
    end
  end
end
