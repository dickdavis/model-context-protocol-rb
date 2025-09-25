require "spec_helper"

RSpec.describe ModelContextProtocol::Server::Instrumentation::Registry do
  subject(:registry) { described_class.new }

  describe "#enabled?" do
    it "defaults to false" do
      expect(registry.enabled?).to be false
    end

    it "returns true after enable!" do
      registry.enable!
      expect(registry.enabled?).to be true
    end

    it "returns false after disable!" do
      registry.enable!
      registry.disable!
      expect(registry.enabled?).to be false
    end
  end

  describe "#add_callback" do
    it "stores callbacks for later execution" do
      callback_called = false
      registry.add_callback { |event| callback_called = true }
      registry.enable!

      registry.instrument(method: "test", request_id: "123") do
        "result"
      end

      expect(callback_called).to be true
    end
  end

  describe "#register_collector" do
    let(:timing_collector) { ModelContextProtocol::Server::Instrumentation::TimingCollector.new }

    it "stores collectors for instrumentation" do
      registry.register_collector(:timing, timing_collector)
      registry.enable!

      event = nil
      registry.add_callback { |e| event = e }

      registry.instrument(method: "test", request_id: "123") do
        sleep(0.001)
        "result"
      end

      expect(event.metrics[:cpu_time_ms]).to be_a(Float)
    end
  end

  describe "#instrument" do
    context "when disabled" do
      it "yields without instrumentation" do
        result = registry.instrument(method: "test", request_id: "123") do
          "result"
        end
        expect(result).to eq("result")
      end

      it "does not call callbacks" do
        callback_called = false
        registry.add_callback { |event| callback_called = true }

        registry.instrument(method: "test", request_id: "123") do
          "result"
        end

        expect(callback_called).to be false
      end
    end

    context "when enabled" do
      before { registry.enable! }

      it "yields the block and returns result" do
        result = registry.instrument(method: "test", request_id: "123") do
          "expected_result"
        end
        expect(result).to eq("expected_result")
      end

      it "calls callbacks with event data" do
        events = []
        registry.add_callback { |event| events << event }

        registry.instrument(method: "tools/call", request_id: "req-123") do
          "result"
        end

        expect(events.size).to eq(1)
        event = events.first
        expect(event.method).to eq("tools/call")
        expect(event.request_id).to eq("req-123")
        expect(event.metrics[:duration_ms]).to be_a(Float)
      end

      it "handles errors and still calls callbacks" do
        events = []
        registry.add_callback { |event| events << event }

        expect do
          registry.instrument(method: "test", request_id: "123") do
            raise StandardError, "test error"
          end
        end.to raise_error(StandardError, "test error")

        expect(events.size).to eq(1)
        events.first
        # Error handling removed from Event - errors should be handled elsewhere
      end

      it "sets thread context during execution" do
        context_captured = nil

        registry.instrument(method: "test", request_id: "123") do
          context_captured = Thread.current[:mcp_instrumentation_context]
          "result"
        end

        expect(context_captured).to be_a(Hash)
      end

      it "clears thread context after execution" do
        registry.instrument(method: "test", request_id: "123") do
          "result"
        end

        expect(Thread.current[:mcp_instrumentation_context]).to be_nil
      end
    end
  end
end
