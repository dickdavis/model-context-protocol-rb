require_relative "base_collector"

module ModelContextProtocol
  class Server
    module Instrumentation
      class RedisCollector < BaseCollector
        def initialize(pool_manager)
          @pool_manager = pool_manager
        end

        def before_request(context)
          context[:redis_operations] = []
          context[:redis_pool_stats_before] = pool_stats
          context[:redis_collector] = self
        end

        def after_request(context, result)
          context[:redis_pool_stats_after] = pool_stats
        end

        def collect_metrics(context)
          operations = context[:redis_operations] || []

          metrics = {
            redis_operations_count: operations.size
          }

          if operations.any?
            total_latency = operations.sum { |op| op[:duration_ms] }
            metrics[:redis_total_latency_ms] = total_latency.round(2)
            metrics[:redis_avg_latency_ms] = (total_latency / operations.size).round(2)
            metrics[:redis_operations_by_command] = operations
              .group_by { |op| op[:command] }
              .transform_values(&:size)
          end

          if context[:redis_pool_stats_before]
            metrics[:redis_pool_stats] = {
              before: context[:redis_pool_stats_before],
              after: context[:redis_pool_stats_after]
            }
          end

          metrics
        end

        def record_operation(command, duration_ms)
          Thread.current[:mcp_instrumentation_context]&.[](:redis_operations)&.push({
            command: command,
            duration_ms: duration_ms
          })
        end

        private

        def pool_stats
          return nil unless @pool_manager&.pool
          @pool_manager.stats
        end
      end
    end
  end
end
