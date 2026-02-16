require "json"

module ModelContextProtocol
  class Server::StreamableHttpTransport
    class SessionMessageQueue
      QUEUE_KEY_PREFIX = "session_messages:"
      DEFAULT_TTL = 3600  # 1 hour
      MAX_MESSAGES = 1000

      def initialize(redis_client, session_id, ttl: DEFAULT_TTL)
        @redis = redis_client
        @session_id = session_id
        @queue_key = "#{QUEUE_KEY_PREFIX}#{session_id}"
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

      def has_messages?
        @redis.exists(@queue_key) > 0
      rescue
        false
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
