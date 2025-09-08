require "json"

module ModelContextProtocol
  class Server::StreamableHttpTransport
    class NotificationQueue
      QUEUE_KEY_PREFIX = "notifications:"
      DEFAULT_MAX_SIZE = 1000

      def initialize(redis_client, server_instance, max_size: DEFAULT_MAX_SIZE)
        @redis = redis_client
        @server_instance = server_instance
        @queue_key = "#{QUEUE_KEY_PREFIX}#{server_instance}"
        @max_size = max_size
      end

      def push(notification)
        notification_json = notification.to_json

        @redis.multi do |multi|
          multi.lpush(@queue_key, notification_json)
          multi.ltrim(@queue_key, 0, @max_size - 1)
        end
      end

      def pop
        notification_json = @redis.rpop(@queue_key)
        return nil unless notification_json

        JSON.parse(notification_json)
      end

      def pop_all
        notification_jsons = @redis.multi do |multi|
          multi.lrange(@queue_key, 0, -1)
          multi.del(@queue_key)
        end.first

        return [] if notification_jsons.empty?

        notification_jsons.reverse.map do |notification_json|
          JSON.parse(notification_json)
        end
      end

      def peek_all
        notification_jsons = @redis.lrange(@queue_key, 0, -1)
        return [] if notification_jsons.empty?

        notification_jsons.reverse.map do |notification_json|
          JSON.parse(notification_json)
        end
      end

      def size
        @redis.llen(@queue_key)
      end

      def empty?
        size == 0
      end

      def clear
        @redis.del(@queue_key)
      end

      def push_bulk(notifications)
        return if notifications.empty?

        notification_jsons = notifications.map(&:to_json)

        @redis.multi do |multi|
          notification_jsons.each do |json|
            multi.lpush(@queue_key, json)
          end
          multi.ltrim(@queue_key, 0, @max_size - 1)
        end
      end
    end
  end
end
