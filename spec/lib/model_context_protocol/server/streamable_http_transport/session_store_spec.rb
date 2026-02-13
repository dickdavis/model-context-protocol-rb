# frozen_string_literal: true

require "spec_helper"

RSpec.describe ModelContextProtocol::Server::StreamableHttpTransport::SessionStore do
  let(:redis) { MockRedis.new }
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

  before do
    redis.flushdb
  end

  describe "#create_session" do
    it "creates a session with proper data structure" do
      result = session_store.create_session(session_id, session_data)

      aggregate_failures do
        expect(result).to eq(session_id)
        expect(redis.exists("session:#{session_id}")).to eq(1)
      end

      session_hash = redis.hgetall("session:#{session_id}")

      aggregate_failures do
        expect(JSON.parse(session_hash["id"])).to eq(session_id)
        expect(JSON.parse(session_hash["server_instance"])).to eq(server_instance)
        expect(JSON.parse(session_hash["context"])).to eq({"user_id" => 123, "tenant" => "acme"})
        expect(JSON.parse(session_hash["active_stream"])).to eq(false)
        expect(session_hash["last_activity"]).not_to be_nil
        expect(session_hash["created_at"]).not_to be_nil
      end
    end

    it "sets TTL on the session" do
      session_store.create_session(session_id, session_data)

      ttl = redis.ttl("session:#{session_id}")

      aggregate_failures do
        expect(ttl).to be > 0
        expect(ttl).to be <= 300
      end
    end

    it "handles missing optional data gracefully" do
      minimal_data = {server_instance: server_instance}
      result = session_store.create_session(session_id, minimal_data)
      expect(result).to eq(session_id)

      session_hash = redis.hgetall("session:#{session_id}")

      aggregate_failures do
        expect(JSON.parse(session_hash["context"])).to eq({})
        expect(session_hash["created_at"]).not_to be_nil
      end
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

      aggregate_failures do
        expect(session_store.session_has_active_stream?(session_id)).to eq(true)
        expect(session_store.get_session_server(session_id)).to eq(stream_server)
      end
    end

    it "updates last_activity timestamp" do
      old_activity = JSON.parse(redis.hget("session:#{session_id}", "last_activity"))

      sleep 0.01
      session_store.mark_stream_active(session_id, stream_server)

      new_activity = JSON.parse(redis.hget("session:#{session_id}", "last_activity"))
      expect(new_activity).to be > old_activity
    end

    it "refreshes session TTL" do
      redis.expire("session:#{session_id}", 100)

      session_store.mark_stream_active(session_id, stream_server)

      ttl = redis.ttl("session:#{session_id}")
      expect(ttl).to be > 250
    end

    it "uses atomic operations" do
      session_store.mark_stream_active(session_id, stream_server)

      session_hash = redis.hgetall("session:#{session_id}")

      aggregate_failures do
        expect(JSON.parse(session_hash["active_stream"])).to eq(true)
        expect(JSON.parse(session_hash["stream_server"])).to eq(stream_server)
        expect(session_hash["last_activity"]).not_to be_nil
      end
    end
  end

  describe "#mark_stream_inactive" do
    before do
      session_store.create_session(session_id, session_data)
      session_store.mark_stream_active(session_id, server_instance)
    end

    it "marks session stream as inactive" do
      session_store.mark_stream_inactive(session_id)

      aggregate_failures do
        expect(session_store.session_has_active_stream?(session_id)).to eq(false)
        expect(session_store.get_session_server(session_id)).to be_nil
      end
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
      expect(context).to eq({user_id: 123, tenant: "acme"})
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

  describe "#queue_message_for_session" do
    let(:message) { {"method" => "test", "params" => {"data" => "hello"}} }

    context "when session exists" do
      before { session_store.create_session(session_id, session_data) }

      it "queues message for the session" do
        result = session_store.queue_message_for_session(session_id, message)
        expect(result).to eq(true)

        messages = session_store.poll_messages_for_session(session_id)
        expect(messages).to contain_exactly(message)
      end

      it "handles multiple messages" do
        message1 = {"test" => "message1"}
        message2 = {"test" => "message2"}

        session_store.queue_message_for_session(session_id, message1)
        session_store.queue_message_for_session(session_id, message2)

        messages = session_store.poll_messages_for_session(session_id)
        expect(messages).to contain_exactly(message1, message2)
      end
    end

    context "when session does not exist" do
      it "returns false" do
        result = session_store.queue_message_for_session("nonexistent", message)
        expect(result).to eq(false)
      end
    end
  end

  describe "#poll_messages_for_session" do
    let(:message1) { {"method" => "test1", "params" => {"data" => "hello1"}} }
    let(:message2) { {"method" => "test2", "params" => {"data" => "hello2"}} }

    context "when session has messages" do
      before do
        session_store.create_session(session_id, session_data)
        session_store.queue_message_for_session(session_id, message1)
        session_store.queue_message_for_session(session_id, message2)
      end

      it "returns all messages and clears the queue" do
        messages = session_store.poll_messages_for_session(session_id)
        expect(messages).to contain_exactly(message1, message2)

        messages_again = session_store.poll_messages_for_session(session_id)
        expect(messages_again).to eq([])
      end
    end

    context "when session has no messages" do
      before { session_store.create_session(session_id, session_data) }

      it "returns empty array" do
        messages = session_store.poll_messages_for_session(session_id)
        expect(messages).to eq([])
      end
    end

    context "when session does not exist" do
      it "returns empty array" do
        messages = session_store.poll_messages_for_session("nonexistent")
        expect(messages).to eq([])
      end
    end
  end

  describe "#get_sessions_with_messages" do
    let(:session_id_1) { SecureRandom.uuid }
    let(:session_id_2) { SecureRandom.uuid }
    let(:session_id_3) { SecureRandom.uuid }

    before do
      session_store.create_session(session_id_1, session_data)
      session_store.create_session(session_id_2, session_data)
      session_store.create_session(session_id_3, session_data)
    end

    it "returns only sessions that have pending messages" do
      session_store.queue_message_for_session(session_id_1, {"test" => "msg1"})
      session_store.queue_message_for_session(session_id_3, {"test" => "msg3"})

      sessions = session_store.get_sessions_with_messages

      aggregate_failures do
        expect(sessions).to contain_exactly(session_id_1, session_id_3)
        expect(sessions).not_to include(session_id_2)
      end
    end

    it "returns empty array when no sessions have messages" do
      sessions = session_store.get_sessions_with_messages
      expect(sessions).to eq([])
    end
  end

  describe "#get_all_active_sessions" do
    let(:session_id_1) { SecureRandom.uuid }
    let(:session_id_2) { SecureRandom.uuid }
    let(:session_id_3) { SecureRandom.uuid }

    before do
      session_store.create_session(session_id_1, session_data)
      session_store.create_session(session_id_2, session_data)
      session_store.create_session(session_id_3, session_data)

      session_store.mark_stream_active(session_id_1, "server-1")
      session_store.mark_stream_active(session_id_2, "server-2")
    end

    it "returns only sessions with active streams" do
      active_sessions = session_store.get_all_active_sessions

      aggregate_failures do
        expect(active_sessions).to contain_exactly(session_id_1, session_id_2)
        expect(active_sessions).not_to include(session_id_3)
      end
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
        fresh_redis = MockRedis.new
        fresh_session_store = described_class.new(fresh_redis, ttl: 300)

        active_sessions = fresh_session_store.get_all_active_sessions
        expect(active_sessions).to eq([])
      end
    end
  end

  describe "#store_registered_handlers" do
    before { session_store.create_session(session_id, session_data) }

    it "stores handler names in Redis" do
      session_store.store_registered_handlers(
        session_id,
        prompts: ["prompt1", "prompt2"],
        resources: ["resource1"],
        tools: ["tool1", "tool2", "tool3"]
      )

      session_hash = redis.hgetall("session:#{session_id}")

      aggregate_failures do
        expect(JSON.parse(session_hash["registered_prompts"])).to eq(["prompt1", "prompt2"])
        expect(JSON.parse(session_hash["registered_resources"])).to eq(["resource1"])
        expect(JSON.parse(session_hash["registered_tools"])).to eq(["tool1", "tool2", "tool3"])
      end
    end

    it "refreshes session TTL" do
      redis.expire("session:#{session_id}", 100)

      session_store.store_registered_handlers(
        session_id,
        prompts: [],
        resources: [],
        tools: []
      )

      ttl = redis.ttl("session:#{session_id}")
      expect(ttl).to be > 250
    end

    it "handles empty arrays" do
      session_store.store_registered_handlers(
        session_id,
        prompts: [],
        resources: [],
        tools: []
      )

      handlers = session_store.get_registered_handlers(session_id)

      aggregate_failures do
        expect(handlers[:prompts]).to eq([])
        expect(handlers[:resources]).to eq([])
        expect(handlers[:tools]).to eq([])
      end
    end
  end

  describe "#get_registered_handlers" do
    before { session_store.create_session(session_id, session_data) }

    context "when handlers have been stored" do
      before do
        session_store.store_registered_handlers(
          session_id,
          prompts: ["prompt1"],
          resources: ["resource1", "resource2"],
          tools: ["tool1"]
        )
      end

      it "returns the stored handlers" do
        handlers = session_store.get_registered_handlers(session_id)

        aggregate_failures do
          expect(handlers[:prompts]).to eq(["prompt1"])
          expect(handlers[:resources]).to eq(["resource1", "resource2"])
          expect(handlers[:tools]).to eq(["tool1"])
        end
      end
    end

    context "when no handlers have been stored" do
      it "returns nil" do
        handlers = session_store.get_registered_handlers(session_id)

        expect(handlers).to be_nil
      end
    end

    context "when session does not exist" do
      it "returns nil" do
        handlers = session_store.get_registered_handlers("nonexistent")

        expect(handlers).to be_nil
      end
    end

    context "when only some handler types have been stored" do
      before do
        redis.hset("session:#{session_id}", "registered_prompts", ["prompt1"].to_json)
      end

      it "returns empty arrays for missing types" do
        handlers = session_store.get_registered_handlers(session_id)

        aggregate_failures do
          expect(handlers[:prompts]).to eq(["prompt1"])
          expect(handlers[:resources]).to eq([])
          expect(handlers[:tools]).to eq([])
        end
      end
    end
  end

  describe "integration scenarios" do
    let(:session_id_1) { SecureRandom.uuid }
    let(:session_id_2) { SecureRandom.uuid }
    let(:server_1) { "server-1" }
    let(:server_2) { "server-2" }

    it "handles complete session lifecycle" do
      session_store.create_session(session_id_1, session_data.merge(server_instance: server_1))
      aggregate_failures do
        expect(session_store.session_exists?(session_id_1)).to eq(true)
        expect(session_store.session_has_active_stream?(session_id_1)).to eq(false)
      end

      session_store.mark_stream_active(session_id_1, server_2)
      aggregate_failures do
        expect(session_store.session_has_active_stream?(session_id_1)).to eq(true)
        expect(session_store.get_session_server(session_id_1)).to eq(server_2)
      end

      expect(session_store.queue_message_for_session(session_id_1, {"test" => "message"})).to eq(true)

      session_store.mark_stream_inactive(session_id_1)
      aggregate_failures do
        expect(session_store.session_has_active_stream?(session_id_1)).to eq(false)
        expect(session_store.get_session_server(session_id_1)).to be_nil
      end

      session_store.cleanup_session(session_id_1)
      expect(session_store.session_exists?(session_id_1)).to eq(false)
    end

    it "handles cross-server session management" do
      session_store.create_session(session_id_1, session_data.merge(server_instance: server_1))
      session_store.mark_stream_active(session_id_1, server_2)

      aggregate_failures do
        expect(session_store.get_session_server(session_id_1)).to eq(server_2)
        expect(session_store.queue_message_for_session(session_id_1, {"from" => "server_1"})).to eq(true)
      end
    end
  end
end
