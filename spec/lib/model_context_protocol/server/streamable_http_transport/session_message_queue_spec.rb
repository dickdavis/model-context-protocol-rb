# frozen_string_literal: true

require "spec_helper"

RSpec.describe ModelContextProtocol::Server::StreamableHttpTransport::SessionMessageQueue do
  let(:redis) { MockRedis.new }
  let(:session_id) { SecureRandom.uuid }
  let(:queue) { described_class.new(redis, session_id, ttl: 300) }

  before do
    redis.flushdb
  end

  describe "#initialize" do
    it "creates a queue with the correct configuration" do
      aggregate_failures do
        expect(queue.instance_variable_get(:@session_id)).to eq(session_id)
        expect(queue.instance_variable_get(:@ttl)).to eq(300)
        expect(queue.instance_variable_get(:@queue_key)).to eq("session_messages:#{session_id}")
        expect(queue.instance_variable_get(:@lock_key)).to eq("session_lock:#{session_id}")
      end
    end

    it "uses default TTL when not specified" do
      default_queue = described_class.new(redis, session_id)
      expect(default_queue.instance_variable_get(:@ttl)).to eq(3600)
    end
  end

  describe "#push_message" do
    let(:message) { {"method" => "test", "params" => {"data" => "hello"}} }

    it "adds a message to the queue" do
      queue.push_message(message)

      aggregate_failures do
        expect(queue.has_messages?).to eq(true)
        expect(queue.message_count).to eq(1)
      end
    end

    it "serializes hash messages as JSON" do
      queue.push_message(message)

      raw_messages = redis.lrange("session_messages:#{session_id}", 0, -1)
      expect(raw_messages.first).to eq(message.to_json)
    end

    it "handles string messages" do
      string_message = "plain text message"
      queue.push_message(string_message)

      raw_messages = redis.lrange("session_messages:#{session_id}", 0, -1)
      expect(raw_messages.first).to eq(string_message)
    end

    it "sets TTL on the queue" do
      queue.push_message(message)

      ttl = redis.ttl("session_messages:#{session_id}")
      aggregate_failures do
        expect(ttl).to be > 0
        expect(ttl).to be <= 300
      end
    end

    it "enforces maximum message limit" do
      1010.times do |i|
        queue.push_message({"test" => i})
      end

      expect(queue.message_count).to eq(1000)
    end
  end

  describe "#push_messages" do
    let(:messages) do
      [
        {"method" => "test1", "params" => {"data" => "hello1"}},
        {"method" => "test2", "params" => {"data" => "hello2"}},
        {"method" => "test3", "params" => {"data" => "hello3"}}
      ]
    end

    it "adds multiple messages at once" do
      queue.push_messages(messages)

      expect(queue.message_count).to eq(3)
    end

    it "handles empty array gracefully" do
      queue.push_messages([])

      expect(queue.has_messages?).to eq(false)
    end

    it "maintains FIFO order for bulk operations" do
      queue.push_messages(messages)

      result = queue.poll_messages
      expect(result).to eq(messages)
    end

    it "enforces max_size for bulk operations" do
      large_batch = Array.new(1010) { |i| {"test" => i} }
      queue.push_messages(large_batch)

      expect(queue.message_count).to eq(1000)
    end
  end

  describe "#poll_messages" do
    let(:message1) { {"method" => "test1", "params" => {"data" => "hello1"}} }
    let(:message2) { {"method" => "test2", "params" => {"data" => "hello2"}} }

    context "when queue has messages" do
      before do
        queue.push_message(message1)
        queue.push_message(message2)
      end

      it "returns all messages in FIFO order" do
        messages = queue.poll_messages
        expect(messages).to eq([message1, message2])
      end

      it "clears the queue after polling" do
        queue.poll_messages

        aggregate_failures do
          expect(queue.has_messages?).to eq(false)
          expect(queue.message_count).to eq(0)
        end
      end

      it "is atomic - subsequent polls return empty" do
        first_poll = queue.poll_messages
        second_poll = queue.poll_messages

        aggregate_failures do
          expect(first_poll).to eq([message1, message2])
          expect(second_poll).to eq([])
        end
      end
    end

    context "when queue is empty" do
      it "returns empty array" do
        messages = queue.poll_messages
        expect(messages).to eq([])
      end
    end

    it "handles Redis errors gracefully" do
      allow(redis).to receive(:eval).and_raise(MockRedis::ConnectionError)

      messages = queue.poll_messages
      expect(messages).to eq([])
    end
  end

  describe "#peek_messages" do
    let(:message1) { {"method" => "test1", "params" => {"data" => "hello1"}} }
    let(:message2) { {"method" => "test2", "params" => {"data" => "hello2"}} }

    context "when queue has messages" do
      before do
        queue.push_message(message1)
        queue.push_message(message2)
      end

      it "returns all messages without removing them" do
        messages = queue.peek_messages

        aggregate_failures do
          expect(messages).to eq([message1, message2])
          expect(queue.message_count).to eq(2)
        end
      end

      it "returns messages in FIFO order" do
        messages = queue.peek_messages
        expect(messages).to eq([message1, message2])
      end
    end

    context "when queue is empty" do
      it "returns empty array" do
        messages = queue.peek_messages
        expect(messages).to eq([])
      end
    end

    it "handles Redis errors gracefully" do
      allow(redis).to receive(:lrange).and_raise(MockRedis::ConnectionError)

      messages = queue.peek_messages
      expect(messages).to eq([])
    end
  end

  describe "#has_messages?" do
    it "returns false when queue is empty" do
      expect(queue.has_messages?).to eq(false)
    end

    it "returns true when queue has messages" do
      queue.push_message({"test" => "message"})
      expect(queue.has_messages?).to eq(true)
    end

    it "handles Redis errors gracefully" do
      allow(redis).to receive(:exists).and_raise(MockRedis::ConnectionError)

      expect(queue.has_messages?).to eq(false)
    end
  end

  describe "#message_count" do
    it "returns 0 for empty queue" do
      expect(queue.message_count).to eq(0)
    end

    it "returns correct count after adding messages" do
      queue.push_message({"test1" => "message1"})
      queue.push_message({"test2" => "message2"})

      expect(queue.message_count).to eq(2)
    end

    it "updates correctly after polling messages" do
      queue.push_message({"test" => "message"})
      expect(queue.message_count).to eq(1)

      queue.poll_messages
      expect(queue.message_count).to eq(0)
    end

    it "handles Redis errors gracefully" do
      allow(redis).to receive(:llen).and_raise(MockRedis::ConnectionError)

      expect(queue.message_count).to eq(0)
    end
  end

  describe "#clear" do
    before do
      queue.push_message({"test1" => "message1"})
      queue.push_message({"test2" => "message2"})
    end

    it "removes all messages from the queue" do
      expect(queue.message_count).to eq(2)

      queue.clear

      aggregate_failures do
        expect(queue.message_count).to eq(0)
        expect(queue.has_messages?).to eq(false)
      end
    end

    it "works on empty queue without error" do
      queue.clear
      queue.clear

      expect(queue.message_count).to eq(0)
    end

    it "handles Redis errors gracefully" do
      allow(redis).to receive(:del).and_raise(MockRedis::ConnectionError)

      expect { queue.clear }.not_to raise_error
    end
  end

  describe "#with_lock" do
    it "acquires and releases lock successfully" do
      result = queue.with_lock do
        "locked operation"
      end

      expect(result).to eq(true)
    end

    it "executes the block when lock is acquired" do
      executed = false

      queue.with_lock do
        executed = true
      end

      expect(executed).to eq(true)
    end

    it "returns false when lock cannot be acquired" do
      redis.set("session_lock:#{session_id}", "other-lock-id", nx: true, ex: 5)

      result = queue.with_lock(timeout: 1) do
        "should not execute"
      end

      expect(result).to eq(false)
    end

    it "releases lock even if block raises error" do
      expect do
        queue.with_lock do
          raise "test error"
        end
      end.to raise_error("test error")

      lock_key = "session_lock:#{session_id}"
      expect(redis.exists(lock_key)).to eq(0)

      result = queue.with_lock do
        "second attempt"
      end

      expect(result).to eq(true)
    end

    it "only releases lock if it owns it" do
      result = queue.with_lock do
        "locked operation"
      end

      expect(result).to eq(true)
    end
  end

  describe "JSON serialization" do
    it "properly serializes and deserializes complex data structures" do
      complex_message = {
        "method" => "complex_test",
        "params" => {
          "nested" => {
            "array" => [1, 2, 3],
            "boolean" => true,
            "null" => nil
          }
        }
      }

      queue.push_message(complex_message)
      messages = queue.poll_messages

      expect(messages.first).to eq(complex_message)
    end

    it "handles malformed JSON gracefully" do
      redis.lpush("session_messages:#{session_id}", "invalid json{")

      messages = queue.poll_messages
      expect(messages.first).to eq("invalid json{")
    end
  end
end
