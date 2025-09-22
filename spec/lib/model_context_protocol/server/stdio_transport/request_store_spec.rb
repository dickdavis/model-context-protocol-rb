require "spec_helper"

RSpec.describe ModelContextProtocol::Server::StdioTransport::RequestStore do
  subject(:store) { described_class.new }

  describe "#register_request" do
    it "registers a request with current thread" do
      request_id = "test-request-123"

      store.register_request(request_id)

      request = store.get_request(request_id)
      expect(request).to include(
        thread: Thread.current,
        cancelled: false,
        started_at: be_a(Time)
      )
    end

    it "registers a request with specific thread" do
      request_id = "test-request-456"
      test_thread = Thread.new { sleep 0.1 }

      store.register_request(request_id, test_thread)

      request = store.get_request(request_id)
      expect(request[:thread]).to eq(test_thread)

      test_thread.kill
      test_thread.join
    end

    it "tracks start time" do
      request_id = "test-request-789"
      start_time = Time.now

      store.register_request(request_id)

      request = store.get_request(request_id)
      expect(request[:started_at]).to be >= start_time
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
        original_request = store.get_request(request_id)

        store.mark_cancelled(request_id)

        updated_request = store.get_request(request_id)
        aggregate_failures do
          expect(updated_request[:thread]).to eq(original_request[:thread])
          expect(updated_request[:started_at]).to eq(original_request[:started_at])
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

      it "removes the request" do
        removed_data = store.unregister_request(request_id)

        expect(removed_data).to include(
          thread: Thread.current,
          cancelled: false
        )
        expect(store.get_request(request_id)).to be_nil
      end
    end

    context "when request does not exist" do
      it "returns nil" do
        expect(store.unregister_request(request_id)).to be_nil
      end
    end
  end

  describe "#get_request" do
    let(:request_id) { "test-request" }

    context "when request exists" do
      before do
        store.register_request(request_id)
      end

      it "returns a copy of request data" do
        request = store.get_request(request_id)

        expect(request).to include(
          thread: Thread.current,
          cancelled: false,
          started_at: be_a(Time)
        )

        request[:cancelled] = true
        expect(store.cancelled?(request_id)).to be false
      end
    end

    context "when request does not exist" do
      it "returns nil" do
        expect(store.get_request(request_id)).to be_nil
      end
    end
  end

  describe "#active_requests" do
    it "returns empty array when no requests" do
      expect(store.active_requests).to eq([])
    end

    it "returns list of active request IDs" do
      request_ids = ["request-1", "request-2", "request-3"]

      request_ids.each { |id| store.register_request(id) }

      expect(store.active_requests).to match_array(request_ids)
    end

    it "excludes unregistered requests" do
      store.register_request("request-1")
      store.register_request("request-2")
      store.unregister_request("request-1")

      expect(store.active_requests).to eq(["request-2"])
    end
  end

  describe "#cleanup_old_requests" do
    it "removes requests older than specified age" do
      old_request = "old-request"
      new_request = "new-request"

      store.register_request(old_request)
      store.instance_variable_get(:@requests)[old_request][:started_at] = Time.now - 400

      store.register_request(new_request)
      removed = store.cleanup_old_requests(300)

      aggregate_failures do
        expect(removed).to include(old_request)
        expect(store.get_request(old_request)).to be_nil
        expect(store.get_request(new_request)).not_to be_nil
      end
    end

    it "returns list of removed request IDs" do
      store.register_request("request-1")
      store.register_request("request-2")

      old_time = Time.now - 400
      requests = store.instance_variable_get(:@requests)
      requests["request-1"][:started_at] = old_time
      requests["request-2"][:started_at] = old_time

      removed = store.cleanup_old_requests(300)

      expect(removed).to match_array(["request-1", "request-2"])
    end
  end

  describe "thread safety" do
    it "handles concurrent access safely" do
      threads = []
      request_ids = []

      10.times do |i|
        threads << Thread.new do
          request_id = "concurrent-request-#{i}"
          request_ids << request_id
          store.register_request(request_id)
          store.mark_cancelled(request_id) if i.even?
        end
      end

      threads.each(&:join)

      expect(store.active_requests.size).to eq(10)

      cancelled_count = request_ids.count { |id| store.cancelled?(id) }
      expect(cancelled_count).to eq(5)
    end
  end
end
