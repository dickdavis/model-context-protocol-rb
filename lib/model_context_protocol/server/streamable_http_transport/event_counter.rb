module ModelContextProtocol
  class Server::StreamableHttpTransport
    class EventCounter
      COUNTER_KEY_PREFIX = "event_counter:"

      def initialize(redis_client, server_instance)
        @redis = redis_client
        @server_instance = server_instance
        @counter_key = "#{COUNTER_KEY_PREFIX}#{server_instance}"

        if @redis.exists(@counter_key) == 0
          @redis.set(@counter_key, 0)
        end
      end

      def next_event_id
        count = @redis.incr(@counter_key)
        "#{@server_instance}-#{count}"
      end
    end
  end
end
