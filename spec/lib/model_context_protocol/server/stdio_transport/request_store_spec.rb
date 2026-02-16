require "spec_helper"

RSpec.describe ModelContextProtocol::Server::StdioTransport::RequestStore do
  subject(:store) { described_class.new }

  describe "#register_request" do
    it "registers a request with current thread" do
      request_id = "test-request-123"

      store.register_request(request_id)

      aggregate_failures do
        expect(store.cancelled?(request_id)).to be false
        data = store.unregister_request(request_id)
        expect(data).to include(thread: Thread.current, cancelled: false, started_at: be_a(Time))
      end
    end

    it "registers a request with specific thread" do
      request_id = "test-request-456"
      test_thread = Thread.new { sleep 0.1 }

      store.register_request(request_id, test_thread)

      data = store.unregister_request(request_id)
      expect(data[:thread]).to eq(test_thread)

      test_thread.kill
      test_thread.join
    end

    it "tracks start time" do
      request_id = "test-request-789"
      start_time = Time.now

      store.register_request(request_id)

      data = store.unregister_request(request_id)
      expect(data[:started_at]).to be >= start_time
    end
  end

  describe "#mark_cancelled" do
    context "when request exists" do
      let(:request_id) { "existing-request" }

      before do
        store.register_request(request_id)
      end

      it "marks the request as cancelled" do
        expect(store.mark_cancelled(request_id)).to be true
        expect(store.cancelled?(request_id)).to be true
      end

      it "preserves other request data" do
        store.mark_cancelled(request_id)

        data = store.unregister_request(request_id)
        aggregate_failures do
          expect(data[:thread]).to eq(Thread.current)
          expect(data[:started_at]).to be_a(Time)
          expect(data[:cancelled]).to be true
        end
      end
    end

    context "when request does not exist" do
      it "returns false" do
        expect(store.mark_cancelled("nonexistent-request")).to be false
      end
    end
  end

  describe "#cancelled?" do
    let(:request_id) { "test-request" }

    context "when request is not registered" do
      it "returns false" do
        expect(store.cancelled?(request_id)).to be false
      end
    end

    context "when request is registered but not cancelled" do
      before do
        store.register_request(request_id)
      end

      it "returns false" do
        expect(store.cancelled?(request_id)).to be false
      end
    end

    context "when request is cancelled" do
      before do
        store.register_request(request_id)
        store.mark_cancelled(request_id)
      end

      it "returns true" do
        expect(store.cancelled?(request_id)).to be true
      end
    end
  end

  describe "#unregister_request" do
    let(:request_id) { "test-request" }

    context "when request exists" do
      before do
        store.register_request(request_id)
      end

      it "removes the request and returns its data" do
        removed_data = store.unregister_request(request_id)

        aggregate_failures do
          expect(removed_data).to include(thread: Thread.current, cancelled: false)
          expect(store.cancelled?(request_id)).to be false
          expect(store.unregister_request(request_id)).to be_nil
        end
      end
    end

    context "when request does not exist" do
      it "returns nil" do
        expect(store.unregister_request(request_id)).to be_nil
      end
    end
  end

  describe "thread safety" do
    it "handles concurrent access safely" do
      threads = []
      request_ids = (0...10).map { |i| "concurrent-request-#{i}" }

      10.times do |i|
        threads << Thread.new do
          store.register_request(request_ids[i])
          store.mark_cancelled(request_ids[i]) if i.even?
        end
      end

      threads.each(&:join)

      cancelled_count = request_ids.count { |id| store.cancelled?(id) }
      expect(cancelled_count).to eq(5)
    end
  end
end
