require "spec_helper"

RSpec.describe ModelContextProtocol::Server::Instrumentation::RedisCollector do
  let(:pool_manager) { double("RedisPoolManager") }
  subject(:collector) { described_class.new(pool_manager) }
  let(:context) { {} }

  describe "#before_request" do
    let(:stats) { {size: 10, available: 8, idle: 2} }

    before do
      allow(pool_manager).to receive(:pool).and_return(double("pool"))
      allow(pool_manager).to receive(:stats).and_return(stats)
    end

    it "initializes redis operations array in context" do
      collector.before_request(context)
      expect(context[:redis_operations]).to eq([])
    end

    it "captures initial pool stats" do
      collector.before_request(context)
      expect(context[:redis_pool_stats_before]).to eq(stats)
    end

    it "stores itself in context for Redis proxy to use" do
      collector.before_request(context)
      expect(context[:redis_collector]).to eq(collector)
    end
  end

  describe "#after_request" do
    let(:stats_after) { {size: 10, available: 7, idle: 1} }

    before do
      allow(pool_manager).to receive(:pool).and_return(double("pool"))
      allow(pool_manager).to receive(:stats).and_return(stats_after)
      collector.before_request(context)
    end

    it "captures final pool stats" do
      collector.after_request(context, nil)
      expect(context[:redis_pool_stats_after]).to eq(stats_after)
    end
  end

  describe "#record_operation" do
    before do
      allow(pool_manager).to receive(:pool).and_return(double("pool"))
      allow(pool_manager).to receive(:stats).and_return({size: 10, available: 8})
      Thread.current[:mcp_instrumentation_context] = context
      collector.before_request(context)
    end

    after do
      Thread.current[:mcp_instrumentation_context] = nil
    end

    it "records operation in thread context" do
      collector.record_operation("GET", 15.5)

      operations = context[:redis_operations]
      expect(operations.size).to eq(1)
      expect(operations.first).to eq({command: "GET", duration_ms: 15.5})
    end

    it "records multiple operations" do
      collector.record_operation("GET", 10.0)
      collector.record_operation("SET", 12.5)

      operations = context[:redis_operations]
      expect(operations.size).to eq(2)
    end
  end

  describe "#collect_metrics" do
    let(:initial_stats) { {size: 10, available: 8, idle: 2} }
    let(:final_stats) { {size: 10, available: 7, idle: 1} }

    before do
      allow(pool_manager).to receive(:pool).and_return(double("pool"))
      allow(pool_manager).to receive(:stats).and_return(initial_stats, final_stats)
      collector.before_request(context)
    end

    context "with no operations" do
      it "returns basic metrics with zero operations" do
        metrics = collector.collect_metrics(context)
        expect(metrics[:redis_operations_count]).to eq(0)
      end

      it "includes pool stats" do
        collector.after_request(context, nil)
        metrics = collector.collect_metrics(context)

        expect(metrics[:redis_pool_stats]).to eq({
          before: initial_stats,
          after: final_stats
        })
      end
    end

    context "with operations" do
      before do
        context[:redis_operations] = [
          {command: "GET", duration_ms: 10.0},
          {command: "SET", duration_ms: 15.0},
          {command: "GET", duration_ms: 8.0}
        ]
      end

      it "calculates operation count" do
        metrics = collector.collect_metrics(context)
        expect(metrics[:redis_operations_count]).to eq(3)
      end

      it "calculates total and average latency" do
        metrics = collector.collect_metrics(context)
        expect(metrics[:redis_total_latency_ms]).to eq(33.0)
        expect(metrics[:redis_avg_latency_ms]).to eq(11.0)
      end

      it "groups operations by command" do
        metrics = collector.collect_metrics(context)
        expect(metrics[:redis_operations_by_command]).to eq({
          "GET" => 2,
          "SET" => 1
        })
      end
    end

    context "without pool manager" do
      subject(:collector) { described_class.new(nil) }

      it "handles missing pool manager gracefully" do
        metrics = collector.collect_metrics(context)
        expect(metrics[:redis_pool_stats]).to be_nil
      end
    end
  end
end
