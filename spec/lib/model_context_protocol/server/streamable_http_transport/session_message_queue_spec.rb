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

      expect(queue.has_messages?).to eq(true)
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

      expect(queue.poll_messages.length).to eq(1000)
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

        expect(queue.has_messages?).to eq(false)
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
