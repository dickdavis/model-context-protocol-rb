require "spec_helper"

RSpec.describe ModelContextProtocol::Server::StreamableHttpConfiguration do
  subject(:configuration) { described_class.new }

  describe "transport type" do
    it "returns :streamable_http" do
      expect(configuration.transport_type).to eq(:streamable_http)
    end

    it "returns true for supports_list_changed?" do
      expect(configuration.supports_list_changed?).to be true
    end

    it "returns false for apply_environment_variables?" do
      expect(configuration.apply_environment_variables?).to be false
    end
  end

  describe "defaults" do
    it "defaults require_sessions to true" do
      expect(configuration.require_sessions).to be true
    end

    it "defaults validate_origin to true" do
      expect(configuration.validate_origin).to be true
    end

    it "defaults allowed_origins to localhost" do
      expect(configuration.allowed_origins).to eq([
        "http://localhost", "https://localhost",
        "http://127.0.0.1", "https://127.0.0.1"
      ])
    end

    it "defaults session_ttl to 3600" do
      expect(configuration.session_ttl).to eq(3600)
    end

    it "defaults ping_timeout to 10" do
      expect(configuration.ping_timeout).to eq(10)
    end
  end

  describe "redis attribute defaults" do
    it "defaults redis_url to nil" do
      expect(configuration.redis_url).to be_nil
    end

    it "defaults redis_pool_size to 20" do
      expect(configuration.redis_pool_size).to eq(20)
    end

    it "defaults redis_pool_timeout to 5" do
      expect(configuration.redis_pool_timeout).to eq(5)
    end

    it "defaults redis_ssl_params to nil" do
      expect(configuration.redis_ssl_params).to be_nil
    end

    it "defaults redis_enable_reaper to true" do
      expect(configuration.redis_enable_reaper).to be true
    end

    it "defaults redis_reaper_interval to 60" do
      expect(configuration.redis_reaper_interval).to eq(60)
    end

    it "defaults redis_idle_timeout to 300" do
      expect(configuration.redis_idle_timeout).to eq(300)
    end
  end

  describe "custom values" do
    it "allows overriding all transport-specific options" do
      configuration.require_sessions = false
      configuration.validate_origin = false
      configuration.allowed_origins = ["*"]
      configuration.session_ttl = 7200
      configuration.ping_timeout = 30

      aggregate_failures do
        expect(configuration.require_sessions).to be false
        expect(configuration.validate_origin).to be false
        expect(configuration.allowed_origins).to eq(["*"])
        expect(configuration.session_ttl).to eq(7200)
        expect(configuration.ping_timeout).to eq(30)
      end
    end

    it "allows overriding all redis options" do
      configuration.redis_url = "rediss://prod.example.com:6380/1"
      configuration.redis_pool_size = 50
      configuration.redis_pool_timeout = 10
      configuration.redis_ssl_params = {verify_mode: 0}
      configuration.redis_enable_reaper = false
      configuration.redis_reaper_interval = 120
      configuration.redis_idle_timeout = 600

      aggregate_failures do
        expect(configuration.redis_url).to eq("rediss://prod.example.com:6380/1")
        expect(configuration.redis_pool_size).to eq(50)
        expect(configuration.redis_pool_timeout).to eq(10)
        expect(configuration.redis_ssl_params).to eq({verify_mode: 0})
        expect(configuration.redis_enable_reaper).to be false
        expect(configuration.redis_reaper_interval).to eq(120)
        expect(configuration.redis_idle_timeout).to eq(600)
      end
    end
  end

  describe "validation" do
    before do
      configuration.name = "test-server"
      configuration.registry {}
      configuration.version = "1.0.0"
    end

    it "raises error when redis_url is not set" do
      expect { configuration.validate! }.to raise_error(
        ModelContextProtocol::Server::Configuration::InvalidTransportError,
        /streamable_http transport requires a valid Redis URL/
      )
    end

    it "raises error when redis_url is empty" do
      configuration.redis_url = ""
      expect { configuration.validate! }.to raise_error(
        ModelContextProtocol::Server::Configuration::InvalidTransportError,
        /streamable_http transport requires a valid Redis URL/
      )
    end

    it "raises error when redis_url has wrong scheme" do
      configuration.redis_url = "http://localhost:6379"
      expect { configuration.validate! }.to raise_error(
        ModelContextProtocol::Server::Configuration::InvalidTransportError,
        /streamable_http transport requires a valid Redis URL/
      )
    end

    it "validates successfully with redis:// URL" do
      configuration.redis_url = "redis://localhost:6379/15"
      expect { configuration.validate! }.not_to raise_error
    end

    it "validates successfully with rediss:// URL" do
      configuration.redis_url = "rediss://prod.example.com:6380/1"
      expect { configuration.validate! }.not_to raise_error
    end
  end

  describe "setup_transport!" do
    before do
      configuration.name = "test-server"
      configuration.registry {}
      configuration.version = "1.0.0"
      configuration.redis_url = "redis://localhost:6379/15"
    end

    it "configures RedisConfig with redis attributes" do
      configuration.redis_pool_size = 30
      configuration.redis_pool_timeout = 8

      expect(ModelContextProtocol::Server::RedisConfig).to receive(:configure).and_yield(
        ModelContextProtocol::Server::RedisConfig::Configuration.new
      )

      configuration.send(:setup_transport!)
    end
  end

  describe "allows stdout logger" do
    after do
      ModelContextProtocol::Server::GlobalConfig::ServerLogging.reset!
    end

    it "allows stdout logger for streamable_http transport" do
      ModelContextProtocol::Server.configure_server_logging do |config|
        config.logdev = $stdout
      end

      config = described_class.new
      config.name = "test-server"
      config.version = "1.0.0"
      config.registry {}
      config.redis_url = "redis://localhost:6379/15"

      expect { config.validate! }.not_to raise_error
    end
  end
end
