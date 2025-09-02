# frozen_string_literal: true

require "json"
require "securerandom"

module ModelContextProtocol
  class Server
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

      def route_message_to_session(session_id, message)
        server_instance = get_session_server(session_id)
        return false unless server_instance

        # Publish to server-specific channel
        @redis.publish("server:#{server_instance}:messages", {
          session_id: session_id,
          message: message
        }.to_json)
        true
      end

      def subscribe_to_server(server_instance, &block)
        @redis.subscribe("server:#{server_instance}:messages") do |on|
          on.message do |channel, message|
            data = JSON.parse(message)
            yield(data)
          end
        end
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
    end
  end
end
