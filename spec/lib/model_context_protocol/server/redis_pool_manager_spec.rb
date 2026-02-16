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
        expect(manager.instance_variable_get(:@ssl_params)).to be_nil
      end
    end

    it "stores ssl_params when provided" do
      ssl_params = {verify_mode: OpenSSL::SSL::VERIFY_NONE}
      manager_with_ssl = described_class.new(
        redis_url: redis_url,
        pool_size: pool_size,
        pool_timeout: pool_timeout,
        ssl_params: ssl_params
      )
      expect(manager_with_ssl.instance_variable_get(:@ssl_params)).to eq(ssl_params)
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

    context "with ssl_params" do
      let(:ssl_params) { {verify_mode: OpenSSL::SSL::VERIFY_NONE} }
      let(:redis_double) { double("redis", close: nil, ping: "PONG") }

      context "when URL uses rediss://" do
        let(:redis_url) { "rediss://localhost:6379/15" }
        subject(:manager) do
          described_class.new(
            redis_url: redis_url,
            pool_size: pool_size,
            pool_timeout: pool_timeout,
            ssl_params: ssl_params
          )
        end

        it "passes ssl_params to Redis.new" do
          expect(Redis).to receive(:new).with(
            url: redis_url,
            ssl_params: ssl_params
          ).and_return(redis_double)

          manager.start
          # Force pool to create a connection
          manager.pool.with { |_| }
        end
      end

      context "when URL uses redis://" do
        let(:redis_url) { "redis://localhost:6379/15" }
        subject(:manager) do
          described_class.new(
            redis_url: redis_url,
            pool_size: pool_size,
            pool_timeout: pool_timeout,
            ssl_params: ssl_params
          )
        end

        it "does not pass ssl_params to Redis.new" do
          expect(Redis).to receive(:new).with(url: redis_url).and_return(redis_double)

          manager.start
          # Force pool to create a connection
          manager.pool.with { |_| }
        end
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

      reaper = manager.instance_variable_get(:@reaper_thread)
      expect(reaper).to be_alive

      manager.shutdown

      expect(reaper.alive?).to be_falsey
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
