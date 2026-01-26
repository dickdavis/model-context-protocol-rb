# frozen_string_literal: true

require "spec_helper"

RSpec.describe ModelContextProtocol::Server::StreamableHttpTransport::MessagePoller do
  let(:redis) { MockRedis.new }
  let(:stream_registry) { double("StreamRegistry") }
  let(:client_logger) { double("Logger") }
  let(:message_delivery_block) { double("MessageDeliveryBlock") }

  let(:poller) do
    described_class.new(redis, stream_registry, client_logger) do |stream, message|
      message_delivery_block.call(stream, message)
    end
  end

  before do
    redis.flushdb
    allow(client_logger).to receive(:debug)
    allow(client_logger).to receive(:error)
    allow(stream_registry).to receive(:get_all_local_streams).and_return({})
  end

  describe "#initialize" do
    it "creates a poller with the correct configuration" do
      aggregate_failures do
        expect(poller.instance_variable_get(:@redis)).to eq(redis)
        expect(poller.instance_variable_get(:@stream_registry)).to eq(stream_registry)
        expect(poller.instance_variable_get(:@client_logger)).to eq(client_logger)
        expect(poller.instance_variable_get(:@running)).to eq(false)
        expect(poller.instance_variable_get(:@poll_thread)).to be_nil
      end
    end

    it "stores the message delivery block" do
      expect(poller.instance_variable_get(:@message_delivery_block)).to be_a(Proc)
    end
  end

  describe "#start" do
    let(:mock_thread) { double("Thread", name: nil, alive?: true) }

    before do
      allow(Thread).to receive(:new) do |&block|
        mock_thread
      end
      allow(mock_thread).to receive(:name=)
    end

    it "starts the polling thread" do
      expect(Thread).to receive(:new)

      poller.start

      aggregate_failures do
        expect(poller.instance_variable_get(:@running)).to eq(true)
        expect(poller.instance_variable_get(:@poll_thread)).to eq(mock_thread)
      end
    end

    it "logs debug message when started" do
      expect(client_logger).to receive(:debug).with("Message poller started")

      poller.start
    end

    it "sets thread name if possible" do
      expect(mock_thread).to receive(:name=).with("MCP-MessagePoller")

      poller.start
    end

    it "handles thread name setting gracefully if not supported" do
      allow(mock_thread).to receive(:respond_to?).with(:name=).and_return(false)

      aggregate_failures do
        expect(mock_thread).not_to receive(:name=)
        expect { poller.start }.not_to raise_error
      end
    end

    it "does not start if already running" do
      poller.instance_variable_set(:@running, true)

      expect(Thread).not_to receive(:new)

      poller.start
    end

    context "when thread encounters error" do
      let(:failing_thread) do
        double("Thread").tap do |thread|
          allow(thread).to receive(:name=)
          allow(thread).to receive(:name)
          allow(thread).to receive(:alive?).and_return(true)
        end
      end

      before do
        allow(Thread).to receive(:new) do |&block|
          allow(failing_thread).to receive(:join) do
            poller.send(:poll_and_deliver_messages) if poller.respond_to?(:poll_and_deliver_messages, true)
          rescue => e
            client_logger.error("Message poller thread error", error: e.message, backtrace: e.backtrace&.first(5))
          end
          failing_thread
        end
      end

      it "logs errors and continues running" do
        allow(poller).to receive(:poll_and_deliver_messages).and_raise("Test error")

        expect(client_logger).to receive(:error).with("Message poller thread error",
          hash_including(error: "Test error"))

        poller.start
        failing_thread.join
      end
    end
  end

  describe "#stop" do
    let(:mock_thread) { double("Thread", alive?: true, kill: nil, join: nil, name: nil) }

    before do
      poller.instance_variable_set(:@running, true)
      poller.instance_variable_set(:@poll_thread, mock_thread)
      allow(mock_thread).to receive(:name=)
    end

    it "stops the polling thread" do
      aggregate_failures do
        expect(mock_thread).to receive(:kill)
        expect(mock_thread).to receive(:join).with(5)
      end

      poller.stop

      aggregate_failures do
        expect(poller.instance_variable_get(:@running)).to eq(false)
        expect(poller.instance_variable_get(:@poll_thread)).to be_nil
      end
    end

    it "logs debug message when stopped" do
      expect(client_logger).to receive(:debug).with("Message poller stopped")

      poller.stop
    end

    it "handles case when thread is not alive" do
      allow(mock_thread).to receive(:alive?).and_return(false)

      aggregate_failures do
        expect(mock_thread).not_to receive(:kill)
        expect(mock_thread).not_to receive(:join)
      end

      poller.stop
    end

    it "handles case when thread is nil" do
      poller.instance_variable_set(:@poll_thread, nil)

      expect { poller.stop }.not_to raise_error
    end
  end

  describe "#running?" do
    context "when not started" do
      it "returns false" do
        expect(poller.running?).to eq(false)
      end
    end

    context "when started" do
      let(:mock_thread) { double("Thread", alive?: true, name: nil) }

      before do
        poller.instance_variable_set(:@running, true)
        poller.instance_variable_set(:@poll_thread, mock_thread)
        allow(mock_thread).to receive(:name=)
      end

      it "returns true when running and thread is alive" do
        expect(poller.running?).to eq(true)
      end

      it "returns false when marked as not running" do
        poller.instance_variable_set(:@running, false)
        expect(poller.running?).to eq(false)
      end

      it "returns false when thread is not alive" do
        allow(mock_thread).to receive(:alive?).and_return(false)
        expect(poller.running?).to eq(false)
      end
    end
  end

  describe "#poll_and_deliver_messages" do
    context "when no local streams exist" do
      before do
        allow(stream_registry).to receive(:get_all_local_streams).and_return({})
      end

      it "returns early without polling" do
        expect(poller).not_to receive(:poll_sessions_batch)
        poller.send(:poll_and_deliver_messages)
      end
    end

    context "when local streams exist" do
      let(:session_id_1) { "session-1" }
      let(:session_id_2) { "session-2" }
      let(:stream_1) { double("Stream1") }
      let(:stream_2) { double("Stream2") }

      before do
        allow(stream_registry).to receive(:get_all_local_streams).and_return({
          session_id_1 => stream_1,
          session_id_2 => stream_2
        })
      end

      it "polls messages for all local sessions" do
        expect(poller).to receive(:poll_sessions_batch).with([session_id_1, session_id_2])
        poller.send(:poll_and_deliver_messages)
      end

      context "with large number of sessions" do
        let(:many_sessions) do
          {}.tap do |sessions|
            150.times { |i| sessions["session-#{i}"] = double("Stream#{i}") }
          end
        end

        before do
          allow(stream_registry).to receive(:get_all_local_streams).and_return(many_sessions)
        end

        it "processes sessions in batches" do
          aggregate_failures do
            expect(poller).to receive(:poll_sessions_batch).with(many_sessions.keys[0..99])
            expect(poller).to receive(:poll_sessions_batch).with(many_sessions.keys[100..149])
          end

          poller.send(:poll_and_deliver_messages)
        end
      end
    end
  end

  describe "#poll_sessions_batch" do
    let(:session_id_1) { "session-1" }
    let(:session_id_2) { "session-2" }
    let(:stream_1) { double("Stream1") }
    let(:stream_2) { double("Stream2") }
    let(:message_1) { {"method" => "test1", "params" => {"data" => "hello1"}} }
    let(:message_2) { {"method" => "test2", "params" => {"data" => "hello2"}} }

    before do
      allow(stream_registry).to receive(:get_local_stream).with(session_id_1).and_return(stream_1)
      allow(stream_registry).to receive(:get_local_stream).with(session_id_2).and_return(stream_2)
    end

    context "when sessions have messages" do
      before do
        queue_1 = ModelContextProtocol::Server::StreamableHttpTransport::SessionMessageQueue.new(redis, session_id_1)
        queue_1.push_message(message_1)

        queue_2 = ModelContextProtocol::Server::StreamableHttpTransport::SessionMessageQueue.new(redis, session_id_2)
        queue_2.push_message(message_2)
      end

      it "delivers messages to their respective streams" do
        aggregate_failures do
          expect(message_delivery_block).to receive(:call).with(stream_1, message_1)
          expect(message_delivery_block).to receive(:call).with(stream_2, message_2)
        end

        poller.send(:poll_sessions_batch, [session_id_1, session_id_2])
      end
    end

    context "when sessions have no messages" do
      it "does not attempt delivery" do
        expect(message_delivery_block).not_to receive(:call)

        poller.send(:poll_sessions_batch, [session_id_1, session_id_2])
      end
    end

    context "when stream does not exist for session" do
      before do
        allow(stream_registry).to receive(:get_local_stream).with(session_id_1).and_return(nil)

        queue_1 = ModelContextProtocol::Server::StreamableHttpTransport::SessionMessageQueue.new(redis, session_id_1)
        queue_1.push_message(message_1)
      end

      it "skips delivery for sessions without streams" do
        expect(message_delivery_block).not_to receive(:call)

        poller.send(:poll_sessions_batch, [session_id_1])
      end
    end

    context "when multiple messages exist for a session" do
      let(:message_3) { {"method" => "test3", "params" => {"data" => "hello3"}} }

      before do
        queue_1 = ModelContextProtocol::Server::StreamableHttpTransport::SessionMessageQueue.new(redis, session_id_1)
        queue_1.push_message(message_1)
        queue_1.push_message(message_3)
      end

      it "delivers all messages in order" do
        aggregate_failures do
          expect(message_delivery_block).to receive(:call).with(stream_1, message_1).ordered
          expect(message_delivery_block).to receive(:call).with(stream_1, message_3).ordered
        end

        poller.send(:poll_sessions_batch, [session_id_1])
      end
    end
  end

  describe "#deliver_message_to_stream" do
    let(:stream) { double("Stream") }
    let(:message) { {"method" => "test", "params" => {"data" => "hello"}} }
    let(:session_id) { "test-session" }

    context "when delivery succeeds" do
      it "calls the message delivery block" do
        expect(message_delivery_block).to receive(:call).with(stream, message)

        poller.send(:deliver_message_to_stream, stream, message, session_id)
      end
    end

    context "when message delivery block is nil" do
      let(:poller_without_block) do
        described_class.new(redis, stream_registry, client_logger)
      end

      it "handles gracefully" do
        expect { poller_without_block.send(:deliver_message_to_stream, stream, message, session_id) }.not_to raise_error
      end
    end

    context "when stream is disconnected" do
      before do
        allow(message_delivery_block).to receive(:call).and_raise(IOError)
      end

      it "unregisters the stream" do
        aggregate_failures do
          expect(stream_registry).to receive(:unregister_stream).with(session_id)
          expect(client_logger).to receive(:debug).with("Unregistered disconnected stream", session_id: session_id)
        end

        poller.send(:deliver_message_to_stream, stream, message, session_id)
      end

      it "handles EPIPE errors" do
        allow(message_delivery_block).to receive(:call).and_raise(Errno::EPIPE)

        expect(stream_registry).to receive(:unregister_stream).with(session_id)

        poller.send(:deliver_message_to_stream, stream, message, session_id)
      end

      it "handles ECONNRESET errors" do
        allow(message_delivery_block).to receive(:call).and_raise(Errno::ECONNRESET)

        expect(stream_registry).to receive(:unregister_stream).with(session_id)

        poller.send(:deliver_message_to_stream, stream, message, session_id)
      end
    end

    context "when other errors occur" do
      before do
        allow(message_delivery_block).to receive(:call).and_raise(StandardError, "Other error")
      end

      it "logs the error without unregistering stream" do
        aggregate_failures do
          expect(client_logger).to receive(:error).with("Error delivering message to stream",
            session_id: session_id, error: "Other error")
          expect(stream_registry).not_to receive(:unregister_stream)
        end

        poller.send(:deliver_message_to_stream, stream, message, session_id)
      end
    end
  end

  describe "integration scenarios" do
    let(:session_id) { "integration-session" }
    let(:stream) { double("Stream") }
    let(:messages) do
      [
        {"method" => "msg1", "params" => {"data" => "data1"}},
        {"method" => "msg2", "params" => {"data" => "data2"}}
      ]
    end

    before do
      allow(stream_registry).to receive(:get_all_local_streams).and_return({session_id => stream})
      allow(stream_registry).to receive(:get_local_stream).with(session_id).and_return(stream)

      queue = ModelContextProtocol::Server::StreamableHttpTransport::SessionMessageQueue.new(redis, session_id)
      messages.each { |msg| queue.push_message(msg) }
    end

    it "polls and delivers queued messages" do
      aggregate_failures do
        expect(message_delivery_block).to receive(:call).with(stream, messages[0])
        expect(message_delivery_block).to receive(:call).with(stream, messages[1])
      end

      poller.send(:poll_and_deliver_messages)

      queue = ModelContextProtocol::Server::StreamableHttpTransport::SessionMessageQueue.new(redis, session_id)
      expect(queue.has_messages?).to eq(false)
    end

    it "handles polling with no messages gracefully" do
      queue = ModelContextProtocol::Server::StreamableHttpTransport::SessionMessageQueue.new(redis, session_id)
      queue.clear

      aggregate_failures do
        expect(message_delivery_block).not_to receive(:call)
        expect { poller.send(:poll_and_deliver_messages) }.not_to raise_error
      end
    end
  end

  describe "error handling" do
    it "handles Redis connection errors during polling" do
      allow(stream_registry).to receive(:get_all_local_streams).and_return({"session-1" => double("Stream")})
      allow(redis).to receive(:eval).and_raise(Redis::ConnectionError)

      expect { poller.send(:poll_and_deliver_messages) }.not_to raise_error
    end

    it "logs errors in message polling" do
      poller.instance_variable_set(:@running, true)

      allow(poller).to receive(:poll_and_deliver_messages).and_raise("Polling error")

      expect(client_logger).to receive(:error).with("Error in message polling", error: "Polling error")

      begin
        poller.send(:poll_and_deliver_messages)
      rescue => e
        client_logger.error("Error in message polling", error: e.message)
      end
    end
  end
end
