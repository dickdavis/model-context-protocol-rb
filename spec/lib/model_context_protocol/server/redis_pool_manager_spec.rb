require "spec_helper"

RSpec.describe ModelContextProtocol::Server::RedisPoolManager do
  subject(:manager) { described_class.new(redis_url:, pool_size:, pool_timeout:) }

  let(:redis_url) { "redis://localhost:6379/15" }
  let(:pool_size) { 5 }
  let(:pool_timeout) { 2 }

  describe "#initialize" do
    it "stores configuration" do
      aggregate_failures do
        expect(manager.instance_variable_get(:@redis_url)).to eq(redis_url)
        expect(manager.instance_variable_get(:@pool_size)).to eq(5)
        expect(manager.instance_variable_get(:@pool_timeout)).to eq(2)
      end
    end

    it "does not create pool immediately" do
      expect(manager.pool).to be_nil
    end

    it "sets default reaper configuration" do
      reaper_config = manager.instance_variable_get(:@reaper_config)
      expect(reaper_config).to eq({
        enabled: false,
        interval: 60,
        idle_timeout: 300
      })
    end
  end

  describe "#configure_reaper" do
    it "updates reaper configuration" do
      manager.configure_reaper(
        enabled: true,
        interval: 30,
        idle_timeout: 120
      )

      reaper_config = manager.instance_variable_get(:@reaper_config)
      expect(reaper_config).to eq({
        enabled: true,
        interval: 30,
        idle_timeout: 120
      })
    end
  end

  describe "#start" do
    context "with valid configuration" do
      it "creates the connection pool" do
        manager.start
        expect(manager.pool).to be_a(ConnectionPool)
      end

      it "creates pool with correct size" do
        manager.start
        expect(manager.pool.size).to eq(5)
      end

      it "returns true on success" do
        expect(manager.start).to be true
      end
    end

    context "with invalid configuration" do
      let(:redis_url) { nil }

      it "raises ArgumentError for missing redis_url" do
        expect { manager.start }.to raise_error(ArgumentError, /redis_url is required/)
      end
    end

    context "with negative pool_size" do
      let(:pool_size) { -1 }

      it "raises ArgumentError" do
        expect { manager.start }.to raise_error(ArgumentError, /pool_size must be positive/)
      end
    end

    context "with negative pool_timeout" do
      let(:pool_timeout) { -1 }

      it "raises ArgumentError" do
        expect { manager.start }.to raise_error(ArgumentError, /pool_timeout must be positive/)
      end
    end

    context "with reaper enabled" do
      before do
        manager.configure_reaper(enabled: true, interval: 1)
      end

      it "starts reaper thread" do
        manager.start

        aggregate_failures do
          expect(manager.reaper_thread).to be_a(Thread)
          expect(manager.reaper_thread).to be_alive
        end

        manager.shutdown
      end

      it "names the reaper thread" do
        manager.start

        expect(manager.reaper_thread.name).to eq("MCP-Redis-Reaper")

        manager.shutdown
      end
    end
  end

  describe "#shutdown" do
    before do
      manager.start
    end

    it "closes the pool" do
      conn = double("conn")
      allow(conn).to receive(:close)

      expect(manager.pool).to receive(:shutdown).and_yield(conn)

      manager.shutdown

      expect(manager.pool).to be_nil
    end

    it "stops reaper thread if running" do
      manager.configure_reaper(enabled: true)
      manager.start

      thread = manager.reaper_thread
      expect(thread).to be_alive

      manager.shutdown

      expect(thread.alive?).to be_falsey
    end
  end

  describe "#healthy?" do
    context "when pool does not exist" do
      it "returns false" do
        expect(manager.healthy?).to be false
      end
    end

    context "when pool exists" do
      before do
        manager.start
      end

      context "and Redis responds to ping" do
        it "returns true" do
          expect(manager.healthy?).to be true
        end
      end

      context "and Redis connection fails" do
        before do
          redis_mock = double("redis")
          allow(redis_mock).to receive(:ping).and_raise(StandardError.new("Connection failed"))
          allow(manager.pool).to receive(:with).and_yield(redis_mock)
        end

        it "returns false" do
          expect(manager.healthy?).to be false
        end
      end

      context "and Redis returns unexpected response" do
        before do
          redis_mock = double("redis")
          allow(redis_mock).to receive(:ping).and_return("UNEXPECTED")
          allow(manager.pool).to receive(:with).and_yield(redis_mock)
        end

        it "returns false" do
          expect(manager.healthy?).to be false
        end
      end
    end
  end

  describe "#reap_now" do
    context "when pool does not exist" do
      it "returns without error" do
        expect { manager.reap_now }.not_to raise_error
      end
    end

    context "when pool exists" do
      before do
        manager.start
      end

      it "calls reap on the pool with default timeout" do
        expect(manager.pool).to receive(:reap).with(idle_seconds: 300)
        manager.reap_now
      end

      it "uses configured idle timeout" do
        manager.configure_reaper(enabled: false, idle_timeout: 600)
        expect(manager.pool).to receive(:reap).with(idle_seconds: 600)
        manager.reap_now
      end

      it "yields connections to close block" do
        conn = double("connection")
        expect(conn).to receive(:close)

        expect(manager.pool).to receive(:reap).with(idle_seconds: 300).and_yield(conn)
        manager.reap_now
      end
    end
  end

  describe "#stats" do
    context "when pool does not exist" do
      it "returns empty hash" do
        expect(manager.stats).to eq({})
      end
    end

    context "when pool exists" do
      before do
        manager.start
      end

      it "returns pool statistics" do
        stats = manager.stats
        aggregate_failures do
          expect(stats).to include(:size, :available, :idle)
          expect(stats[:size]).to eq(5)
          expect(stats[:available]).to eq(5)
          expect(stats[:idle]).to be >= 0
        end
      end
    end
  end

  describe "reaper thread behavior" do
    it "reaps connections at specified intervals" do
      manager.configure_reaper(enabled: true, interval: 0.1)

      expect(manager).to receive(:reap_now).at_least(2).times

      manager.start
      sleep 0.25
      manager.shutdown
    end

    it "handles reaper errors gracefully" do
      manager.configure_reaper(enabled: true, interval: 0.1)

      allow(manager).to receive(:reap_now).and_raise("Reaper error")

      expect {
        manager.start
        sleep 0.15
        manager.shutdown
      }.not_to raise_error
    end
  end
end
