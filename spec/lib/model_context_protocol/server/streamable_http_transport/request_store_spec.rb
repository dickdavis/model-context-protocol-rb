require "spec_helper"

RSpec.describe ModelContextProtocol::Server::StreamableHttpTransport::RequestStore do
  subject(:store) { described_class.new(mock_redis, server_instance) }

  let(:mock_redis) { MockRedis.new }
  let(:server_instance) { "test-server-123" }

  before(:each) do
    mock_redis.flushdb
  end

  describe "#register_request" do
    let(:request_id) { "test-request-123" }
    let(:session_id) { "session-456" }

    context "with session ID" do
      it "stores request data in Redis" do
        store.register_request(request_id, session_id)

        request_data = JSON.parse(mock_redis.get("request:active:#{request_id}"))
        expect(request_data).to include(
          "session_id" => session_id,
          "server_instance" => server_instance,
          "started_at" => be_a(Numeric)
        )
      end

      it "creates session association" do
        store.register_request(request_id, session_id)

        expect(mock_redis.get("request:session:#{session_id}:#{request_id}")).to eq("true")
      end

      it "sets TTL on all keys" do
        store.register_request(request_id, session_id)

        aggregate_failures do
          expect(mock_redis.ttl("request:active:#{request_id}")).to be > 0
          expect(mock_redis.ttl("request:session:#{session_id}:#{request_id}")).to be > 0
        end
      end
    end

    context "without session ID" do
      it "stores request data without session association" do
        store.register_request(request_id)

        request_data = JSON.parse(mock_redis.get("request:active:#{request_id}"))
        expect(request_data).to include(
          "session_id" => nil,
          "server_instance" => server_instance
        )
      end

      it "does not create session association key" do
        store.register_request(request_id)

        session_keys = mock_redis.keys("request:session:*")
        expect(session_keys).to be_empty
      end
    end
  end

  describe "#mark_cancelled" do
    let(:request_id) { "test-request-123" }
    let(:reason) { "User requested cancellation" }

    it "sets cancellation flag in Redis" do
      result = store.mark_cancelled(request_id, reason)

      expect(result).to be true

      cancellation_data = JSON.parse(mock_redis.get("request:cancelled:#{request_id}"))
      expect(cancellation_data).to include(
        "cancelled_at" => be_a(Numeric),
        "reason" => reason
      )
    end

    it "sets TTL on cancellation key" do
      store.mark_cancelled(request_id, reason)

      expect(mock_redis.ttl("request:cancelled:#{request_id}")).to be > 0
    end

    context "without reason" do
      it "stores cancellation without reason" do
        store.mark_cancelled(request_id)

        cancellation_data = JSON.parse(mock_redis.get("request:cancelled:#{request_id}"))
        expect(cancellation_data).to include(
          "cancelled_at" => be_a(Numeric),
          "reason" => nil
        )
      end
    end
  end

  describe "#cancelled?" do
    let(:request_id) { "test-request-123" }

    context "when request is not cancelled" do
      it "returns false" do
        expect(store.cancelled?(request_id)).to be false
      end
    end

    context "when request is cancelled" do
      before do
        store.mark_cancelled(request_id, "Test cancellation")
      end

      it "returns true" do
        expect(store.cancelled?(request_id)).to be true
      end
    end
  end

  describe "#unregister_request" do
    let(:request_id) { "test-request-123" }
    let(:session_id) { "session-456" }

    context "when request exists with session" do
      before do
        store.register_request(request_id, session_id)
        store.mark_cancelled(request_id, "test")
      end

      it "removes all associated keys" do
        store.unregister_request(request_id)

        aggregate_failures do
          expect(mock_redis.get("request:active:#{request_id}")).to be_nil
          expect(mock_redis.get("request:cancelled:#{request_id}")).to be_nil
          expect(mock_redis.get("request:session:#{session_id}:#{request_id}")).to be_nil
        end
      end
    end

    context "when request exists without session" do
      before do
        store.register_request(request_id)
        store.mark_cancelled(request_id, "test")
      end

      it "removes request and cancellation keys" do
        store.unregister_request(request_id)

        aggregate_failures do
          expect(mock_redis.get("request:active:#{request_id}")).to be_nil
          expect(mock_redis.get("request:cancelled:#{request_id}")).to be_nil
        end
      end
    end

    context "when request does not exist" do
      it "handles gracefully" do
        expect { store.unregister_request(request_id) }.not_to raise_error
      end
    end
  end

  describe "#cleanup_session_requests" do
    let(:session_id) { "session-456" }
    let(:request_ids) { ["req-1", "req-2", "req-3"] }

    before do
      request_ids.each do |req_id|
        store.register_request(req_id, session_id)
        store.mark_cancelled(req_id, "test") if req_id == "req-2"
      end
    end

    it "removes all requests for the session" do
      removed = store.cleanup_session_requests(session_id)

      aggregate_failures do
        expect(removed).to match_array(request_ids)

        request_ids.each do |req_id|
          expect(mock_redis.get("request:active:#{req_id}")).to be_nil
          expect(mock_redis.get("request:cancelled:#{req_id}")).to be_nil
          expect(mock_redis.get("request:session:#{session_id}:#{req_id}")).to be_nil
        end
      end
    end

    context "when session has no requests" do
      it "returns empty array" do
        removed = store.cleanup_session_requests("nonexistent-session")
        expect(removed).to eq([])
      end
    end
  end

  describe "TTL behavior" do
    let(:request_id) { "test-request-123" }
    let(:session_id) { "session-456" }

    it "sets appropriate TTL on request registration" do
      store.register_request(request_id, session_id)

      ttl = mock_redis.ttl("request:active:#{request_id}")
      expect(ttl).to be_within(5).of(60) # Default TTL
    end

    it "sets appropriate TTL on cancellation" do
      store.mark_cancelled(request_id, "test")

      ttl = mock_redis.ttl("request:cancelled:#{request_id}")
      expect(ttl).to be_within(5).of(60) # Default TTL
    end
  end
end
