require "json"
require "securerandom"
require_relative "session_message_queue"

module ModelContextProtocol
  class Server::StreamableHttpTransport
    class SessionStore
      def initialize(redis_client, ttl: 3600)
        @redis = redis_client
        @ttl = ttl
      end

      def create_session(session_id, data)
        session_data = {
          id: session_id,
          server_instance: data[:server_instance],
          context: data[:context] || {},
          created_at: data[:created_at] || Time.now.to_f,
          last_activity: Time.now.to_f,
          active_stream: false
        }

        @redis.hset("session:#{session_id}", session_data.transform_values(&:to_json))
        @redis.expire("session:#{session_id}", @ttl)
        session_id
      end

      def mark_stream_active(session_id, server_instance)
        @redis.multi do |multi|
          multi.hset("session:#{session_id}",
            "active_stream", true.to_json,
            "stream_server", server_instance.to_json,
            "last_activity", Time.now.to_f.to_json)
          multi.expire("session:#{session_id}", @ttl)
        end
      end

      def mark_stream_inactive(session_id)
        @redis.multi do |multi|
          multi.hset("session:#{session_id}",
            "active_stream", false.to_json,
            "stream_server", nil.to_json,
            "last_activity", Time.now.to_f.to_json)
          multi.expire("session:#{session_id}", @ttl)
        end
      end

      def get_session_server(session_id)
        server_data = @redis.hget("session:#{session_id}", "stream_server")
        server_data ? JSON.parse(server_data) : nil
      end

      def session_exists?(session_id)
        @redis.exists("session:#{session_id}") == 1
      end

      def session_has_active_stream?(session_id)
        stream_data = @redis.hget("session:#{session_id}", "active_stream")
        stream_data ? JSON.parse(stream_data) : false
      end

      def get_session_context(session_id)
        context_data = @redis.hget("session:#{session_id}", "context")
        context_data ? JSON.parse(context_data) : {}
      end

      def cleanup_session(session_id)
        @redis.del("session:#{session_id}")
      end

      def queue_message_for_session(session_id, message)
        return false unless session_exists?(session_id)

        queue = SessionMessageQueue.new(@redis, session_id, ttl: @ttl)
        queue.push_message(message)
        true
      rescue
        false
      end

      def poll_messages_for_session(session_id)
        return [] unless session_exists?(session_id)

        queue = SessionMessageQueue.new(@redis, session_id, ttl: @ttl)
        queue.poll_messages
      rescue
        []
      end

      def get_sessions_with_messages
        session_keys = @redis.keys("session:*")
        sessions_with_messages = []

        session_keys.each do |key|
          session_id = key.sub("session:", "")
          queue = SessionMessageQueue.new(@redis, session_id, ttl: @ttl)
          if queue.has_messages?
            sessions_with_messages << session_id
          end
        end

        sessions_with_messages
      rescue
        []
      end

      def get_all_active_sessions
        keys = @redis.keys("session:*")
        active_sessions = []

        keys.each do |key|
          session_id = key.sub("session:", "")
          if session_has_active_stream?(session_id)
            active_sessions << session_id
          end
        end

        active_sessions
      end

      def store_registered_handlers(session_id, prompts:, resources:, tools:)
        @redis.hset("session:#{session_id}",
          "registered_prompts", prompts.to_json,
          "registered_resources", resources.to_json,
          "registered_tools", tools.to_json)
        @redis.expire("session:#{session_id}", @ttl)
      end

      def get_registered_handlers(session_id)
        data = @redis.hmget("session:#{session_id}",
          "registered_prompts", "registered_resources", "registered_tools")

        # Return nil if none of the fields have meaningful data
        return nil if data.all? { |d| d.nil? || d.empty? }

        {
          prompts: data[0] && !data[0].empty? ? JSON.parse(data[0]) : [],
          resources: data[1] && !data[1].empty? ? JSON.parse(data[1]) : [],
          tools: data[2] && !data[2].empty? ? JSON.parse(data[2]) : []
        }
      end
    end
  end
end
