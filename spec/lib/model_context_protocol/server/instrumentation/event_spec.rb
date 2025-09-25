require "spec_helper"

RSpec.describe ModelContextProtocol::Server::Instrumentation::Event do
  subject(:event) do
    described_class[
      method: "tools/call",
      request_id: "req-123",
      metrics: {
        started_at: started_at.iso8601(6),
        ended_at: ended_at.iso8601(6),
        duration_ms: duration_ms
      }
    ]
  end

  let(:started_at) { Time.now }
  let(:ended_at) { started_at + 0.1 }
  let(:duration_ms) { 100.0 }

  describe "#serialized" do
    it "returns a hash with all event data" do
      result = event.serialized

      aggregate_failures do
        expect(result).to include(
          method: "tools/call",
          request_id: "req-123"
        )
        expect(result[:metrics]).to include(
          duration_ms: 100.0
        )
        expect(result[:metrics][:started_at]).to be_a(String)
        expect(result[:metrics][:ended_at]).to be_a(String)
      end
    end

    context "with additional metrics" do
      subject(:event) do
        described_class[
          method: "tools/call",
          request_id: "req-123",
          metrics: {
            started_at: started_at.iso8601(6),
            ended_at: ended_at.iso8601(6),
            duration_ms: duration_ms,
            cpu_time_ms: 50.0,
            redis_operations_count: 2
          }
        ]
      end

      it "includes all metrics in serialized output" do
        result = event.serialized
        expect(result[:metrics]).to include(
          cpu_time_ms: 50.0,
          redis_operations_count: 2,
          duration_ms: 100.0
        )
      end
    end
  end
end
