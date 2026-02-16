require "spec_helper"

RSpec.describe ModelContextProtocol::Server::StreamableHttpTransport::ServerRequestStore do
  subject(:store) { described_class.new(mock_redis, server_instance) }

  let(:mock_redis) { MockRedis.new }
  let(:server_instance) { "test-server-123" }

  before(:each) do
    mock_redis.flushdb
  end

  describe "#register_request" do
    let(:request_id) { "ping-test-123" }
    let(:session_id) { "session-456" }

    context "with session ID" do
      it "stores request data in Redis" do
        store.register_request(request_id, session_id, type: :ping)

        request_data = JSON.parse(mock_redis.get("server_request:pending:#{request_id}"))
        expect(request_data).to include(
          "session_id" => session_id,
          "server_instance" => server_instance,
          "type" => "ping",
          "created_at" => be_a(Numeric)
        )
      end

      it "creates session association" do
        store.register_request(request_id, session_id, type: :ping)

        expect(mock_redis.get("server_request:session:#{session_id}:#{request_id}")).to eq("true")
      end

      it "sets TTL on all keys" do
        store.register_request(request_id, session_id, type: :ping)

        aggregate_failures do
          expect(mock_redis.ttl("server_request:pending:#{request_id}")).to be > 0
          expect(mock_redis.ttl("server_request:session:#{session_id}:#{request_id}")).to be > 0
        end
      end
    end

    context "without session ID" do
      it "stores request data without session association" do
        store.register_request(request_id, nil, type: :ping)

        request_data = JSON.parse(mock_redis.get("server_request:pending:#{request_id}"))
        expect(request_data).to include(
          "session_id" => nil,
          "server_instance" => server_instance,
          "type" => "ping",
          "created_at" => be_a(Numeric)
        )
      end

      it "does not create session association" do
        store.register_request(request_id, nil, type: :ping)

        keys = mock_redis.keys("server_request:session:*")
        expect(keys).to be_empty
      end
    end
  end

  describe "#pending?" do
    let(:request_id) { "ping-test-123" }

    it "returns true for pending requests" do
      store.register_request(request_id)

      expect(store.pending?(request_id)).to be true
    end

    it "returns false for non-existent requests" do
      expect(store.pending?("non-existent")).to be false
    end
  end

  describe "#mark_completed" do
    let(:request_id) { "ping-test-123" }
    let(:session_id) { "session-456" }

    context "when request exists" do
      before do
        store.register_request(request_id, session_id, type: :ping)
      end

      it "returns true and removes the request" do
        expect(store.mark_completed(request_id)).to be true
        expect(store.pending?(request_id)).to be false
      end

      it "cleans up all associated keys" do
        store.mark_completed(request_id)

        aggregate_failures do
          expect(mock_redis.get("server_request:pending:#{request_id}")).to be_nil
          expect(mock_redis.get("server_request:session:#{session_id}:#{request_id}")).to be_nil
        end
      end
    end

    context "when request does not exist" do
      it "returns false" do
        expect(store.mark_completed("non-existent")).to be false
      end
    end
  end

  describe "#get_request" do
    let(:request_id) { "ping-test-123" }
    let(:session_id) { "session-456" }

    it "returns request data for existing requests" do
      store.register_request(request_id, session_id, type: :ping)

      request_data = store.get_request(request_id)
      expect(request_data).to include(
        "session_id" => session_id,
        "server_instance" => server_instance,
        "type" => "ping",
        "created_at" => be_a(Numeric)
      )
    end

    it "returns nil for non-existent requests" do
      expect(store.get_request("non-existent")).to be_nil
    end
  end

  describe "#get_expired_requests" do
    let(:request_id1) { "ping-test-123" }
    let(:request_id2) { "ping-test-456" }
    let(:session_id) { "session-789" }

    before do
      # Mock Time.now to control timestamps
      allow(Time).to receive(:now).and_return(Time.at(1000))
      store.register_request(request_id1, session_id, type: :ping)

      allow(Time).to receive(:now).and_return(Time.at(1015))
      store.register_request(request_id2, session_id, type: :ping)
    end

    it "returns requests older than timeout" do
      allow(Time).to receive(:now).and_return(Time.at(1020))

      expired_requests = store.get_expired_requests(10)

      expect(expired_requests).to have_attributes(size: 1)
      expect(expired_requests.first).to include(
        request_id: request_id1,
        session_id: session_id,
        type: "ping"
      )
    end

    it "does not return requests within timeout" do
      allow(Time).to receive(:now).and_return(Time.at(1005))

      expired_requests = store.get_expired_requests(10)

      expect(expired_requests).to be_empty
    end
  end

  describe "#cleanup_session_requests" do
    let(:session_id) { "session-456" }
    let(:request_id1) { "ping-test-123" }
    let(:request_id2) { "ping-test-456" }

    before do
      store.register_request(request_id1, session_id, type: :ping)
      store.register_request(request_id2, session_id, type: :ping)
    end

    it "removes all requests for a session" do
      cleaned_ids = store.cleanup_session_requests(session_id)

      aggregate_failures do
        expect(cleaned_ids).to contain_exactly(request_id1, request_id2)
        expect(store.pending?(request_id1)).to be false
        expect(store.pending?(request_id2)).to be false
      end
    end

    it "removes session association keys" do
      store.cleanup_session_requests(session_id)

      keys = mock_redis.keys("server_request:session:#{session_id}:*")
      expect(keys).to be_empty
    end
  end
end
