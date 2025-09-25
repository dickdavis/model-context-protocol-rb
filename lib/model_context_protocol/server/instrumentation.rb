require_relative "instrumentation/event"
require_relative "instrumentation/base_collector"
require_relative "instrumentation/timing_collector"
require_relative "instrumentation/redis_collector"

module ModelContextProtocol
  class Server
    module Instrumentation
      class Registry
        def initialize
          @callbacks = []
          @collectors = {}
          @enabled = false
        end

        def add_callback(&block)
          @callbacks << block
        end

        def register_collector(name, collector)
          @collectors[name] = collector
        end

        def instrument(method:, request_id:)
          return yield unless @enabled

          context = {}
          Thread.current[:mcp_instrumentation_context] = context

          started_at = Time.now

          # Before request hooks
          @collectors.each_value do |collector|
            collector.before_request(context)
          end
          result = nil

          begin
            result = yield
          ensure
            ended_at = Time.now

            # After request hooks
            @collectors.each_value do |collector|
              collector.after_request(context, result)
            end

            # Collect metrics from all collectors
            all_metrics = {}
            @collectors.each do |name, collector|
              metrics = collector.collect_metrics(context)
              all_metrics.merge!(metrics)
            end

            duration_ms = ((ended_at - started_at) * 1000).round(2)

            # Add timing metrics to the collected metrics
            all_metrics[:started_at] = started_at.iso8601(6)
            all_metrics[:ended_at] = ended_at.iso8601(6)
            all_metrics[:duration_ms] = duration_ms

            event = Event[
              method: method,
              request_id: request_id,
              metrics: all_metrics
            ]

            @callbacks.each { |callback| callback.call(event) }

            Thread.current[:mcp_instrumentation_context] = nil
          end
        end

        def enable!
          @enabled = true
        end

        def disable!
          @enabled = false
        end

        def enabled?
          @enabled
        end
      end
    end
  end
end
