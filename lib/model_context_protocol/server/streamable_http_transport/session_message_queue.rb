require "json"
require "securerandom"

module ModelContextProtocol
  class Server::StreamableHttpTransport
    class SessionMessageQueue
      QUEUE_KEY_PREFIX = "session_messages:"
      LOCK_KEY_PREFIX = "session_lock:"
      DEFAULT_TTL = 3600  # 1 hour
      MAX_MESSAGES = 1000
      LOCK_TIMEOUT = 5  # seconds

      def initialize(redis_client, session_id, ttl: DEFAULT_TTL)
        @redis = redis_client
        @session_id = session_id
        @queue_key = "#{QUEUE_KEY_PREFIX}#{session_id}"
        @lock_key = "#{LOCK_KEY_PREFIX}#{session_id}"
        @ttl = ttl
      end

      def push_message(message)
        message_json = serialize_message(message)

        @redis.multi do |multi|
          multi.lpush(@queue_key, message_json)
          multi.expire(@queue_key, @ttl)
          multi.ltrim(@queue_key, 0, MAX_MESSAGES - 1)
        end
      end

      def push_messages(messages)
        return if messages.empty?

        message_jsons = messages.map { |msg| serialize_message(msg) }

        @redis.multi do |multi|
          message_jsons.each do |json|
            multi.lpush(@queue_key, json)
          end
          multi.expire(@queue_key, @ttl)
          multi.ltrim(@queue_key, 0, MAX_MESSAGES - 1)
        end
      end

      def poll_messages
        lua_script = <<~LUA
          local messages = redis.call('lrange', KEYS[1], 0, -1)
          if #messages > 0 then
            redis.call('del', KEYS[1])
          end
          return messages
        LUA

        messages = @redis.eval(lua_script, keys: [@queue_key])
        return [] unless messages && !messages.empty?
        messages.reverse.map { |json| deserialize_message(json) }
      rescue
        []
      end

      def peek_messages
        messages = @redis.lrange(@queue_key, 0, -1)
        messages.reverse.map { |json| deserialize_message(json) }
      rescue
        []
      end

      def has_messages?
        @redis.exists(@queue_key) > 0
      rescue
        false
      end

      def message_count
        @redis.llen(@queue_key)
      rescue
        0
      end

      def clear
        @redis.del(@queue_key)
      rescue
      end

      def with_lock(timeout: LOCK_TIMEOUT, &block)
        lock_id = SecureRandom.hex(16)

        acquired = @redis.set(@lock_key, lock_id, nx: true, ex: timeout)
        return false unless acquired

        begin
          yield
        ensure
          lua_script = <<~LUA
            if redis.call("get", KEYS[1]) == ARGV[1] then
              return redis.call("del", KEYS[1])
            else
              return 0
            end
          LUA
          @redis.eval(lua_script, keys: [@lock_key], argv: [lock_id])
        end

        true
      end

      private

      def serialize_message(message)
        message.is_a?(String) ? message : message.to_json
      end

      def deserialize_message(json)
        JSON.parse(json)
      rescue JSON::ParserError
        json
      end
    end
  end
end
