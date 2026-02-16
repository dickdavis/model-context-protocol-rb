# frozen_string_literal: true

module ModelContextProtocol
  class Server
    class RedisClientProxy
      def initialize(pool)
        @pool = pool
      end

      def get(key)
        with_connection { |redis| redis.get(key) }
      end

      def set(key, value, **options)
        with_connection { |redis| redis.set(key, value, **options) }
      end

      def del(*keys)
        with_connection { |redis| redis.del(*keys) }
      end

      def exists(*keys)
        with_connection { |redis| redis.exists(*keys) }
      end

      def expire(key, seconds)
        with_connection { |redis| redis.expire(key, seconds) }
      end

      def ttl(key)
        with_connection { |redis| redis.ttl(key) }
      end

      def hget(key, field)
        with_connection { |redis| redis.hget(key, field) }
      end

      def hset(key, *args)
        with_connection { |redis| redis.hset(key, *args) }
      end

      def hmget(key, *fields)
        with_connection { |redis| redis.hmget(key, *fields) }
      end

      def lpush(key, *values)
        with_connection { |redis| redis.lpush(key, *values) }
      end

      def rpop(key)
        with_connection { |redis| redis.rpop(key) }
      end

      def lrange(key, start, stop)
        with_connection { |redis| redis.lrange(key, start, stop) }
      end

      def llen(key)
        with_connection { |redis| redis.llen(key) }
      end

      def ltrim(key, start, stop)
        with_connection { |redis| redis.ltrim(key, start, stop) }
      end

      def incr(key)
        with_connection { |redis| redis.incr(key) }
      end

      def keys(pattern)
        with_connection { |redis| redis.keys(pattern) }
      end

      def multi(&block)
        with_connection do |redis|
          redis.multi do |multi|
            multi_wrapper = RedisMultiWrapper.new(multi)
            block.call(multi_wrapper)
          end
        end
      end

      def pipelined(&block)
        with_connection do |redis|
          redis.pipelined do |pipeline|
            pipeline_wrapper = RedisMultiWrapper.new(pipeline)
            block.call(pipeline_wrapper)
          end
        end
      end

      def mget(*keys)
        with_connection { |redis| redis.mget(*keys) }
      end

      def eval(script, keys: [], argv: [])
        with_connection { |redis| redis.eval(script, keys: keys, argv: argv) }
      end

      private

      def with_connection(&block)
        @pool.with(&block)
      end

      # Wrapper for Redis multi/pipeline operations
      class RedisMultiWrapper
        def initialize(multi)
          @multi = multi
        end

        def method_missing(method, *args, **kwargs, &block)
          @multi.send(method, *args, **kwargs, &block)
        end

        def respond_to_missing?(method, include_private = false)
          @multi.respond_to?(method, include_private)
        end
      end
    end
  end
end
