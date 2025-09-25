require "spec_helper"

RSpec.describe ModelContextProtocol::Server::Instrumentation::TimingCollector do
  subject(:collector) { described_class.new }
  let(:context) { {} }

  describe "#before_request" do
    it "sets timing start in context" do
      collector.before_request(context)
      expect(context[:timing_start]).to be_a(Float)
    end
  end

  describe "#after_request" do
    before do
      collector.before_request(context)
      sleep(0.001) # Small delay to ensure measurable CPU time
    end

    it "sets timing end in context" do
      collector.after_request(context, nil)
      expect(context[:timing_end]).to be_a(Float)
      expect(context[:timing_end]).to be > context[:timing_start]
    end
  end

  describe "#collect_metrics" do
    context "with timing data" do
      before do
        collector.before_request(context)
        sleep(0.001)
        collector.after_request(context, nil)
      end

      it "returns CPU time metrics" do
        metrics = collector.collect_metrics(context)
        expect(metrics[:cpu_time_ms]).to be_a(Float)
        expect(metrics[:cpu_time_ms]).to be >= 0
      end
    end

    context "without timing data" do
      it "returns empty hash" do
        metrics = collector.collect_metrics(context)
        expect(metrics).to eq({})
      end
    end
  end
end
