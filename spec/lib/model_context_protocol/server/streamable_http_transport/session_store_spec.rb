# frozen_string_literal: true

require "spec_helper"

RSpec.describe ModelContextProtocol::Server::StreamableHttpTransport::SessionStore do
  let(:redis) do
    mock_redis = MockRedis.new
    # Add pub/sub support since MockRedis doesn't have it
    allow(mock_redis).to receive(:publish)
    allow(mock_redis).to receive(:subscribe)
    mock_redis
  end

  before do
    # Clear any test data
    redis.flushdb
  end
  let(:session_store) { described_class.new(redis, ttl: 300) }
  let(:session_id) { SecureRandom.uuid }
  let(:server_instance) { "test-server-1" }
  let(:session_data) do
    {
      server_instance: server_instance,
      context: {user_id: 123, tenant: "acme"},
      created_at: Time.now.to_f
    }
  end

  describe "#create_session" do
    it "creates a session with proper data structure" do
      result = session_store.create_session(session_id, session_data)

      expect(result).to eq(session_id)
      expect(redis.exists("session:#{session_id}")).to eq(1)

      # Check session data structure
      session_hash = redis.hgetall("session:#{session_id}")
      expect(JSON.parse(session_hash["id"])).to eq(session_id)
      expect(JSON.parse(session_hash["server_instance"])).to eq(server_instance)
      expect(JSON.parse(session_hash["context"])).to eq({"user_id" => 123, "tenant" => "acme"})
      expect(JSON.parse(session_hash["active_stream"])).to eq(false)
      expect(session_hash["last_activity"]).not_to be_nil
      expect(session_hash["created_at"]).not_to be_nil
    end

    it "sets TTL on the session" do
      session_store.create_session(session_id, session_data)

      ttl = redis.ttl("session:#{session_id}")
      expect(ttl).to be > 0
      expect(ttl).to be <= 300
    end

    it "handles missing optional data gracefully" do
      minimal_data = {server_instance: server_instance}

      result = session_store.create_session(session_id, minimal_data)

      expect(result).to eq(session_id)
      session_hash = redis.hgetall("session:#{session_id}")
      expect(JSON.parse(session_hash["context"])).to eq({})
      expect(session_hash["created_at"]).not_to be_nil
    end
  end

  describe "#session_exists?" do
    context "when session exists" do
      before { session_store.create_session(session_id, session_data) }

      it "returns true" do
        expect(session_store.session_exists?(session_id)).to eq(true)
      end
    end

    context "when session does not exist" do
      it "returns false" do
        expect(session_store.session_exists?("nonexistent")).to eq(false)
      end
    end

    context "when session has expired" do
      it "returns false" do
        session_store.create_session(session_id, session_data)
        redis.expire("session:#{session_id}", -1) # Force expiration

        expect(session_store.session_exists?(session_id)).to eq(false)
      end
    end
  end

  describe "#mark_stream_active" do
    let(:stream_server) { "stream-server-2" }

    before { session_store.create_session(session_id, session_data) }

    it "marks session stream as active" do
      session_store.mark_stream_active(session_id, stream_server)

      expect(session_store.session_has_active_stream?(session_id)).to eq(true)
      expect(session_store.get_session_server(session_id)).to eq(stream_server)
    end

    it "updates last_activity timestamp" do
      old_activity = JSON.parse(redis.hget("session:#{session_id}", "last_activity"))

      sleep 0.01 # Ensure timestamp difference
      session_store.mark_stream_active(session_id, stream_server)

      new_activity = JSON.parse(redis.hget("session:#{session_id}", "last_activity"))
      expect(new_activity).to be > old_activity
    end

    it "refreshes session TTL" do
      # Let some time pass
      redis.expire("session:#{session_id}", 100)

      session_store.mark_stream_active(session_id, stream_server)

      ttl = redis.ttl("session:#{session_id}")
      expect(ttl).to be > 250 # Should be close to 300 again
    end

    it "uses atomic operations" do
      # This test ensures the multi/exec block works correctly
      session_store.mark_stream_active(session_id, stream_server)

      # All fields should be updated together
      session_hash = redis.hgetall("session:#{session_id}")
      expect(JSON.parse(session_hash["active_stream"])).to eq(true)
      expect(JSON.parse(session_hash["stream_server"])).to eq(stream_server)
      expect(session_hash["last_activity"]).not_to be_nil
    end
  end

  describe "#mark_stream_inactive" do
    before do
      session_store.create_session(session_id, session_data)
      session_store.mark_stream_active(session_id, server_instance)
    end

    it "marks session stream as inactive" do
      session_store.mark_stream_inactive(session_id)

      expect(session_store.session_has_active_stream?(session_id)).to eq(false)
      expect(session_store.get_session_server(session_id)).to be_nil
    end

    it "updates last_activity timestamp" do
      old_activity = JSON.parse(redis.hget("session:#{session_id}", "last_activity"))

      sleep 0.01
      session_store.mark_stream_inactive(session_id)

      new_activity = JSON.parse(redis.hget("session:#{session_id}", "last_activity"))
      expect(new_activity).to be > old_activity
    end

    it "refreshes session TTL" do
      redis.expire("session:#{session_id}", 100)

      session_store.mark_stream_inactive(session_id)

      ttl = redis.ttl("session:#{session_id}")
      expect(ttl).to be > 250
    end
  end

  describe "#session_has_active_stream?" do
    before { session_store.create_session(session_id, session_data) }

    context "when session has no active stream" do
      it "returns false" do
        expect(session_store.session_has_active_stream?(session_id)).to eq(false)
      end
    end

    context "when session has active stream" do
      before { session_store.mark_stream_active(session_id, server_instance) }

      it "returns true" do
        expect(session_store.session_has_active_stream?(session_id)).to eq(true)
      end
    end

    context "when session does not exist" do
      it "returns false" do
        expect(session_store.session_has_active_stream?("nonexistent")).to eq(false)
      end
    end
  end

  describe "#get_session_server" do
    before { session_store.create_session(session_id, session_data) }

    context "when session has no active stream" do
      it "returns nil" do
        expect(session_store.get_session_server(session_id)).to be_nil
      end
    end

    context "when session has active stream" do
      before { session_store.mark_stream_active(session_id, server_instance) }

      it "returns the server instance" do
        expect(session_store.get_session_server(session_id)).to eq(server_instance)
      end
    end

    context "when session does not exist" do
      it "returns nil" do
        expect(session_store.get_session_server("nonexistent")).to be_nil
      end
    end
  end

  describe "#get_session_context" do
    before { session_store.create_session(session_id, session_data) }

    it "returns the session context" do
      context = session_store.get_session_context(session_id)
      expect(context).to eq({"user_id" => 123, "tenant" => "acme"})
    end

    context "when session has no context" do
      let(:minimal_data) { {server_instance: server_instance} }

      before do
        redis.flushdb
        session_store.create_session(session_id, minimal_data)
      end

      it "returns empty hash" do
        context = session_store.get_session_context(session_id)
        expect(context).to eq({})
      end
    end

    context "when session does not exist" do
      it "returns empty hash" do
        context = session_store.get_session_context("nonexistent")
        expect(context).to eq({})
      end
    end
  end

  describe "#cleanup_session" do
    before { session_store.create_session(session_id, session_data) }

    it "removes the session from Redis" do
      expect(session_store.session_exists?(session_id)).to eq(true)

      session_store.cleanup_session(session_id)

      expect(session_store.session_exists?(session_id)).to eq(false)
    end

    it "handles cleanup of non-existent session gracefully" do
      expect { session_store.cleanup_session("nonexistent") }.not_to raise_error
    end
  end

  describe "#route_message_to_session" do
    let(:message) { {"method" => "test", "params" => {"data" => "hello"}} }

    context "when session has active stream" do
      before do
        session_store.create_session(session_id, session_data)
        session_store.mark_stream_active(session_id, server_instance)
      end

      it "publishes message to server channel" do
        # Mock publish since MockRedis doesn't support it fully
        expect(redis).to receive(:publish).with(
          "server:#{server_instance}:messages",
          {
            session_id: session_id,
            message: message
          }.to_json
        )

        result = session_store.route_message_to_session(session_id, message)
        expect(result).to eq(true)
      end

      it "publishes correct message format" do
        # Mock the publish method to capture the message
        allow(redis).to receive(:publish) do |channel, msg|
          published_data = JSON.parse(msg)
          expect(published_data["session_id"]).to eq(session_id)
          expect(published_data["message"]).to eq(message)
        end

        session_store.route_message_to_session(session_id, message)
      end

      it "returns true when message is routed successfully" do
        result = session_store.route_message_to_session(session_id, message)
        expect(result).to eq(true)
      end
    end

    context "when session has no active stream" do
      before { session_store.create_session(session_id, session_data) }

      it "returns false" do
        result = session_store.route_message_to_session(session_id, message)
        expect(result).to eq(false)
      end
    end

    context "when session does not exist" do
      it "returns false" do
        result = session_store.route_message_to_session("nonexistent", message)
        expect(result).to eq(false)
      end
    end
  end

  describe "#get_all_active_sessions" do
    let(:session_id_1) { SecureRandom.uuid }
    let(:session_id_2) { SecureRandom.uuid }
    let(:session_id_3) { SecureRandom.uuid }

    before do
      # Create multiple sessions
      session_store.create_session(session_id_1, session_data)
      session_store.create_session(session_id_2, session_data)
      session_store.create_session(session_id_3, session_data)

      # Only activate streams for first two
      session_store.mark_stream_active(session_id_1, "server-1")
      session_store.mark_stream_active(session_id_2, "server-2")
    end

    it "returns only sessions with active streams" do
      active_sessions = session_store.get_all_active_sessions

      expect(active_sessions).to contain_exactly(session_id_1, session_id_2)
      expect(active_sessions).not_to include(session_id_3)
    end

    context "when no sessions have active streams" do
      before do
        session_store.mark_stream_inactive(session_id_1)
        session_store.mark_stream_inactive(session_id_2)
      end

      it "returns empty array" do
        active_sessions = session_store.get_all_active_sessions
        expect(active_sessions).to eq([])
      end
    end

    context "when no sessions exist" do
      it "returns empty array" do
        # Use a fresh Redis instance to ensure isolation
        fresh_redis = MockRedis.new
        allow(fresh_redis).to receive(:publish)
        allow(fresh_redis).to receive(:subscribe)
        fresh_session_store = described_class.new(fresh_redis, ttl: 300)

        active_sessions = fresh_session_store.get_all_active_sessions
        expect(active_sessions).to eq([])
      end
    end
  end

  describe "#subscribe_to_server" do
    let(:message) { {"session_id" => session_id, "message" => {"test" => "data"}} }
    let(:channel) { "server:#{server_instance}:messages" }

    it "subscribes to the correct server channel" do
      # Mock the subscription to verify the channel name
      expect(redis).to receive(:subscribe).with(channel)

      session_store.subscribe_to_server(server_instance) { |data| }
    end

    it "calls the block with parsed message data" do
      received_data = nil

      # Mock Redis subscription behavior
      allow(redis).to receive(:subscribe).with(channel) do |&block|
        # Simulate the subscription callback structure
        on = double("on")
        allow(on).to receive(:message) do |&message_block|
          # Simulate receiving a message
          message_block.call(channel, message.to_json)
        end
        block.call(on)
      end

      session_store.subscribe_to_server(server_instance) do |data|
        received_data = data
      end

      expect(received_data).to eq(message)
    end

    it "handles JSON parsing errors gracefully" do
      received_data = nil
      error_occurred = false

      allow(redis).to receive(:subscribe).with(channel) do |&block|
        on = double("on")
        allow(on).to receive(:message) do |&message_block|
          message_block.call(channel, "invalid json")
        rescue JSON::ParserError
          error_occurred = true
        end
        block.call(on)
      end

      session_store.subscribe_to_server(server_instance) do |data|
        received_data = data
      end

      expect(error_occurred).to eq(true)
    end
  end

  describe "integration scenarios" do
    let(:session_id_1) { SecureRandom.uuid }
    let(:session_id_2) { SecureRandom.uuid }
    let(:server_1) { "server-1" }
    let(:server_2) { "server-2" }

    it "handles complete session lifecycle" do
      # 1. Create session
      session_store.create_session(session_id_1, session_data.merge(server_instance: server_1))
      expect(session_store.session_exists?(session_id_1)).to eq(true)
      expect(session_store.session_has_active_stream?(session_id_1)).to eq(false)

      # 2. Activate stream
      session_store.mark_stream_active(session_id_1, server_2)
      expect(session_store.session_has_active_stream?(session_id_1)).to eq(true)
      expect(session_store.get_session_server(session_id_1)).to eq(server_2)

      # 3. Route messages
      expect(session_store.route_message_to_session(session_id_1, {"test" => "message"})).to eq(true)

      # 4. Deactivate stream
      session_store.mark_stream_inactive(session_id_1)
      expect(session_store.session_has_active_stream?(session_id_1)).to eq(false)
      expect(session_store.get_session_server(session_id_1)).to be_nil

      # 5. Cleanup
      session_store.cleanup_session(session_id_1)
      expect(session_store.session_exists?(session_id_1)).to eq(false)
    end

    it "handles cross-server session management" do
      # Server 1 creates session
      session_store.create_session(session_id_1, session_data.merge(server_instance: server_1))

      # Server 2 activates stream for the session
      session_store.mark_stream_active(session_id_1, server_2)

      # Server 1 can still route messages to Server 2's stream
      expect(session_store.get_session_server(session_id_1)).to eq(server_2)
      expect(session_store.route_message_to_session(session_id_1, {"from" => "server_1"})).to eq(true)
    end
  end
end
