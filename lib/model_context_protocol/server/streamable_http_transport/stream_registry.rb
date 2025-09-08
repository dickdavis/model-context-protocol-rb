# frozen_string_literal: true

require "json"

module ModelContextProtocol
  class Server::StreamableHttpTransport
    class StreamRegistry
      STREAM_KEY_PREFIX = "stream:active:"
      HEARTBEAT_KEY_PREFIX = "stream:heartbeat:"
      DEFAULT_TTL = 60 # 1 minute TTL for stream entries

      def initialize(redis_client, server_instance, ttl: DEFAULT_TTL)
        @redis = redis_client
        @server_instance = server_instance
        @ttl = ttl
        @local_streams = {} # Keep local reference for direct stream access
      end

      def register_stream(session_id, stream)
        @local_streams[session_id] = stream

        # Store stream registration in Redis with TTL
        @redis.multi do |multi|
          multi.set("#{STREAM_KEY_PREFIX}#{session_id}", @server_instance, ex: @ttl)
          multi.set("#{HEARTBEAT_KEY_PREFIX}#{session_id}", Time.now.to_f, ex: @ttl)
        end
      end

      def unregister_stream(session_id)
        @local_streams.delete(session_id)

        @redis.multi do |multi|
          multi.del("#{STREAM_KEY_PREFIX}#{session_id}")
          multi.del("#{HEARTBEAT_KEY_PREFIX}#{session_id}")
        end
      end

      def get_local_stream(session_id)
        @local_streams[session_id]
      end

      def has_local_stream?(session_id)
        @local_streams.key?(session_id)
      end

      def get_stream_server(session_id)
        @redis.get("#{STREAM_KEY_PREFIX}#{session_id}")
      end

      def stream_active?(session_id)
        @redis.exists("#{STREAM_KEY_PREFIX}#{session_id}") == 1
      end

      def refresh_heartbeat(session_id)
        @redis.multi do |multi|
          multi.set("#{HEARTBEAT_KEY_PREFIX}#{session_id}", Time.now.to_f, ex: @ttl)
          multi.expire("#{STREAM_KEY_PREFIX}#{session_id}", @ttl)
        end
      end

      def get_all_local_streams
        @local_streams.dup
      end

      def has_any_local_streams?
        !@local_streams.empty?
      end

      def cleanup_expired_streams
        # Get all local stream session IDs
        local_session_ids = @local_streams.keys

        # Check which ones are still active in Redis
        pipeline_results = @redis.pipelined do |pipeline|
          local_session_ids.each do |session_id|
            pipeline.exists("#{STREAM_KEY_PREFIX}#{session_id}")
          end
        end

        # Remove expired streams from local storage
        expired_sessions = []
        local_session_ids.each_with_index do |session_id, index|
          if pipeline_results[index] == 0 # Stream expired in Redis
            @local_streams.delete(session_id)
            expired_sessions << session_id
          end
        end

        expired_sessions
      end

      def get_stale_streams(max_age_seconds = 90)
        current_time = Time.now.to_f
        stale_streams = []

        # Get all heartbeat keys
        heartbeat_keys = @redis.keys("#{HEARTBEAT_KEY_PREFIX}*")

        return stale_streams if heartbeat_keys.empty?

        # Get all heartbeat timestamps
        heartbeat_values = @redis.mget(heartbeat_keys)

        heartbeat_keys.each_with_index do |key, index|
          next unless heartbeat_values[index]

          session_id = key.sub(HEARTBEAT_KEY_PREFIX, "")
          last_heartbeat = heartbeat_values[index].to_f

          if current_time - last_heartbeat > max_age_seconds
            stale_streams << session_id
          end
        end

        stale_streams
      end
    end
  end
end
