require "spec_helper"

RSpec.describe ModelContextProtocol::Server::StreamableHttpTransport::StreamRegistry do
  subject(:registry) { described_class.new(redis, server_instance, ttl: ttl) }

  let(:redis) { MockRedis.new }
  let(:server_instance) { "test-server-123" }
  let(:ttl) { 60 }
  let(:session_id) { "test-session-456" }
  let(:mock_stream) { double("stream") }

  before do
    redis.flushdb
  end

  describe "#initialize" do
    it "creates a registry with the correct configuration" do
      aggregate_failures do
        expect(registry.instance_variable_get(:@redis)).to eq(redis)
        expect(registry.instance_variable_get(:@server_instance)).to eq(server_instance)
        expect(registry.instance_variable_get(:@ttl)).to eq(ttl)
        expect(registry.instance_variable_get(:@local_streams)).to eq({})
      end
    end
  end

  describe "#register_stream" do
    it "stores the stream locally and in Redis" do
      registry.register_stream(session_id, mock_stream)

      aggregate_failures do
        expect(registry.get_local_stream(session_id)).to eq(mock_stream)
        expect(redis.get("stream:active:#{session_id}")).to eq(server_instance)
        expect(redis.ttl("stream:active:#{session_id}")).to be_within(5).of(ttl)
        expect(redis.exists("stream:heartbeat:#{session_id}")).to eq(1)
      end
    end

    it "sets TTL for both stream and heartbeat keys" do
      registry.register_stream(session_id, mock_stream)

      aggregate_failures do
        expect(redis.ttl("stream:active:#{session_id}")).to be_within(5).of(ttl)
        expect(redis.ttl("stream:heartbeat:#{session_id}")).to be_within(5).of(ttl)
      end
    end
  end

  describe "#unregister_stream" do
    before do
      registry.register_stream(session_id, mock_stream)
    end

    it "removes the stream from local storage and Redis" do
      registry.unregister_stream(session_id)

      aggregate_failures do
        expect(registry.get_local_stream(session_id)).to be_nil
        expect(redis.exists("stream:active:#{session_id}")).to eq(0)
        expect(redis.exists("stream:heartbeat:#{session_id}")).to eq(0)
      end
    end
  end

  describe "#get_local_stream" do
    it "returns nil when stream doesn't exist" do
      expect(registry.get_local_stream(session_id)).to be_nil
    end

    it "returns the stream when it exists" do
      registry.register_stream(session_id, mock_stream)
      expect(registry.get_local_stream(session_id)).to eq(mock_stream)
    end
  end

  describe "#has_local_stream?" do
    it "returns false when stream doesn't exist" do
      expect(registry.has_local_stream?(session_id)).to be false
    end

    it "returns true when stream exists" do
      registry.register_stream(session_id, mock_stream)
      expect(registry.has_local_stream?(session_id)).to be true
    end
  end

  describe "#refresh_heartbeat" do
    before do
      registry.register_stream(session_id, mock_stream)
    end

    it "updates the heartbeat timestamp and refreshes TTL" do
      initial_heartbeat = redis.get("stream:heartbeat:#{session_id}")

      sleep 0.01
      registry.refresh_heartbeat(session_id)

      new_heartbeat = redis.get("stream:heartbeat:#{session_id}")

      aggregate_failures do
        expect(new_heartbeat).not_to eq(initial_heartbeat)
        expect(redis.ttl("stream:heartbeat:#{session_id}")).to be_within(5).of(ttl)
        expect(redis.ttl("stream:active:#{session_id}")).to be_within(5).of(ttl)
      end
    end
  end

  describe "#get_all_local_streams" do
    it "returns empty hash when no streams exist" do
      expect(registry.get_all_local_streams).to eq({})
    end

    it "returns all local streams" do
      stream1 = double("stream1")
      stream2 = double("stream2")

      registry.register_stream("session1", stream1)
      registry.register_stream("session2", stream2)

      streams = registry.get_all_local_streams
      expect(streams).to eq({"session1" => stream1, "session2" => stream2})
    end

    it "returns a copy of the streams hash" do
      registry.register_stream(session_id, mock_stream)
      streams = registry.get_all_local_streams
      streams.clear

      expect(registry.get_all_local_streams).not_to be_empty
    end
  end

  describe "#has_any_local_streams?" do
    it "returns false when no streams exist" do
      expect(registry.has_any_local_streams?).to be false
    end

    it "returns true when streams exist" do
      registry.register_stream(session_id, mock_stream)
      expect(registry.has_any_local_streams?).to be true
    end
  end

  describe "#cleanup_expired_streams" do
    it "removes locally stored streams that are expired in Redis" do
      registry.register_stream("session1", double("stream1"))
      registry.register_stream("session2", double("stream2"))

      redis.del("stream:active:session1")

      expired = registry.cleanup_expired_streams

      aggregate_failures do
        expect(expired).to contain_exactly("session1")
        expect(registry.has_local_stream?("session1")).to be false
        expect(registry.has_local_stream?("session2")).to be true
      end
    end

    it "returns empty array when no streams are expired" do
      registry.register_stream(session_id, mock_stream)

      expired = registry.cleanup_expired_streams

      aggregate_failures do
        expect(expired).to be_empty
        expect(registry.has_local_stream?(session_id)).to be true
      end
    end
  end
end
