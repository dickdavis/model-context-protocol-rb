require_relative "session_message_queue"

module ModelContextProtocol
  class Server::StreamableHttpTransport
    class MessagePoller
      POLL_INTERVAL = 0.1  # 100ms
      BATCH_SIZE = 100

      def initialize(redis_client, stream_registry, logger, &message_delivery_block)
        @redis = redis_client
        @stream_registry = stream_registry
        @logger = logger
        @message_delivery_block = message_delivery_block
        @running = false
        @poll_thread = nil
      end

      def start
        return if @running

        @running = true
        @poll_thread = Thread.new do
          poll_loop
        rescue => e
          @logger.error("Message poller thread error", error: e.message, backtrace: e.backtrace.first(5))
          sleep 1
          retry if @running
        end

        @poll_thread.name = "MCP-MessagePoller" if @poll_thread.respond_to?(:name=)

        @logger.debug("Message poller started")
      end

      def stop
        @running = false

        if @poll_thread&.alive?
          @poll_thread.kill
          @poll_thread.join(timeout: 5)
        end

        @poll_thread = nil
        @logger.debug("Message poller stopped")
      end

      def running?
        @running && @poll_thread&.alive?
      end

      private

      def poll_loop
        while @running
          begin
            poll_and_deliver_messages
          rescue => e
            @logger.error("Error in message polling", error: e.message)
          end

          sleep POLL_INTERVAL
        end
      end

      def poll_and_deliver_messages
        local_sessions = @stream_registry.get_all_local_streams.keys
        return if local_sessions.empty?

        local_sessions.each_slice(BATCH_SIZE) do |session_batch|
          poll_sessions_batch(session_batch)
        end
      end

      def poll_sessions_batch(session_ids)
        session_ids.each do |session_id|
          queue = SessionMessageQueue.new(@redis, session_id)
          messages = queue.poll_messages

          next if messages.empty?

          stream = @stream_registry.get_local_stream(session_id)
          next unless stream

          messages.each do |message|
            deliver_message_to_stream(stream, message, session_id)
          end
        end
      end

      def deliver_message_to_stream(stream, message, session_id)
        @message_delivery_block&.call(stream, message)
      rescue IOError, Errno::EPIPE, Errno::ECONNRESET
        @stream_registry.unregister_stream(session_id)
        @logger.debug("Unregistered disconnected stream", session_id: session_id)
      rescue => e
        @logger.error("Error delivering message to stream",
          session_id: session_id, error: e.message)
      end
    end
  end
end
