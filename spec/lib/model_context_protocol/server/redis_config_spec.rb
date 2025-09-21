require "spec_helper"

RSpec.describe ModelContextProtocol::Server::RedisConfig do
  let(:redis_url) { "redis://localhost:6379/15" }
  let(:manager_mock) { instance_double(ModelContextProtocol::Server::RedisPoolManager) }

  before(:each) do
    described_class.instance_variable_set(:@singleton__instance__, nil) if described_class.instance_variable_defined?(:@singleton__instance__)

    allow(ModelContextProtocol::Server::RedisPoolManager).to receive(:new).and_return(manager_mock)
    allow(manager_mock).to receive(:configure_reaper)
    allow(manager_mock).to receive(:start).and_return(true)
    allow(manager_mock).to receive(:shutdown)
    allow(manager_mock).to receive(:pool).and_return(double("pool"))
  end

  after(:each) do
    begin
      described_class.instance.reset!
    rescue
      nil
    end

    described_class.instance_variable_set(:@singleton__instance__, nil) if described_class.instance_variable_defined?(:@singleton__instance__)
  end

  describe ".configure" do
    it "yields configuration object" do
      yielded_config = nil
      described_class.configure do |config|
        config.redis_url = redis_url
        yielded_config = config
      end

      expect(yielded_config).to be_a(ModelContextProtocol::Server::RedisConfig::Configuration)
    end

    it "creates and starts pool manager" do
      expect(ModelContextProtocol::Server::RedisPoolManager).to receive(:new).with(
        redis_url: redis_url,
        pool_size: 20,
        pool_timeout: 5
      ).and_return(manager_mock)
      expect(manager_mock).to receive(:start)

      described_class.configure do |c|
        c.redis_url = redis_url
      end

      expect(described_class.configured?).to be true
    end

    it "configures reaper when enabled" do
      expect(manager_mock).to receive(:configure_reaper).with(
        enabled: true,
        interval: 30,
        idle_timeout: 120
      )

      described_class.configure do |c|
        c.redis_url = redis_url
        c.enable_reaper = true
        c.reaper_interval = 30
        c.idle_timeout = 120
      end
    end

    it "does not configure reaper when disabled" do
      expect(manager_mock).not_to receive(:configure_reaper)

      described_class.configure do |c|
        c.redis_url = redis_url
        c.enable_reaper = false
      end
    end
  end

  describe ".configured?" do
    context "when not configured" do
      it "returns false" do
        expect(described_class.configured?).to be false
      end
    end

    context "when configured" do
      before do
        described_class.configure do |c|
          c.redis_url = redis_url
        end
      end

      it "returns true" do
        expect(described_class.configured?).to be true
      end
    end
  end

  describe ".pool" do
    context "when configured" do
      before do
        described_class.configure do |c|
          c.redis_url = redis_url
        end
      end

      it "returns the connection pool" do
        mock_pool = double("pool")
        allow(manager_mock).to receive(:pool).and_return(mock_pool)
        expect(described_class.pool).to eq(mock_pool)
      end
    end

    context "when not configured" do
      it "raises NotConfiguredError" do
        expect { described_class.pool }.to raise_error(
          ModelContextProtocol::Server::RedisConfig::NotConfiguredError,
          /Redis not configured/
        )
      end
    end
  end

  describe ".shutdown!" do
    context "when configured" do
      before do
        described_class.configure do |c|
          c.redis_url = redis_url
        end
      end

      it "shuts down the manager" do
        expect(manager_mock).to receive(:shutdown)
        described_class.shutdown!
      end
    end

    context "when not configured" do
      it "does not raise error" do
        expect { described_class.shutdown! }.not_to raise_error
      end
    end
  end

  describe "Configuration class" do
    let(:configuration) { described_class::Configuration.new }

    describe "#initialize" do
      it "sets default values" do
        aggregate_failures do
          expect(configuration.redis_url).to be_nil
          expect(configuration.pool_size).to eq(20)
          expect(configuration.pool_timeout).to eq(5)
          expect(configuration.enable_reaper).to be true
          expect(configuration.reaper_interval).to eq(60)
          expect(configuration.idle_timeout).to eq(300)
        end
      end
    end

    describe "attribute setters" do
      it "allows setting redis_url" do
        configuration.redis_url = "redis://test:6379"
        expect(configuration.redis_url).to eq("redis://test:6379")
      end

      it "allows setting pool_size" do
        configuration.pool_size = 10
        expect(configuration.pool_size).to eq(10)
      end

      it "allows setting pool_timeout" do
        configuration.pool_timeout = 3
        expect(configuration.pool_timeout).to eq(3)
      end

      it "allows setting enable_reaper" do
        configuration.enable_reaper = false
        expect(configuration.enable_reaper).to be false
      end

      it "allows setting reaper_interval" do
        configuration.reaper_interval = 120
        expect(configuration.reaper_interval).to eq(120)
      end

      it "allows setting idle_timeout" do
        configuration.idle_timeout = 600
        expect(configuration.idle_timeout).to eq(600)
      end
    end
  end

  describe "error handling" do
    it "propagates validation errors from manager" do
      allow(manager_mock).to receive(:start).and_raise(ArgumentError, "redis_url is required")

      expect {
        described_class.configure do |c|
          c.redis_url = nil
        end
      }.to raise_error(ArgumentError, /redis_url is required/)
    end
  end
end
