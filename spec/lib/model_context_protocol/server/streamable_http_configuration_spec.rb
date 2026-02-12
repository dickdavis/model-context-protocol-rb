require "spec_helper"

RSpec.describe ModelContextProtocol::Server::StreamableHttpConfiguration do
  subject(:configuration) { described_class.new }

  let(:registry) { ModelContextProtocol::Server::Registry.new }

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
    it "defaults require_sessions to false" do
      expect(configuration.require_sessions).to be false
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

  describe "custom values" do
    it "allows overriding all transport-specific options" do
      configuration.require_sessions = true
      configuration.validate_origin = false
      configuration.allowed_origins = ["*"]
      configuration.session_ttl = 7200
      configuration.ping_timeout = 30

      aggregate_failures do
        expect(configuration.require_sessions).to be true
        expect(configuration.validate_origin).to be false
        expect(configuration.allowed_origins).to eq(["*"])
        expect(configuration.session_ttl).to eq(7200)
        expect(configuration.ping_timeout).to eq(30)
      end
    end
  end

  describe "validation" do
    before do
      configuration.name = "test-server"
      configuration.registry = registry
      configuration.version = "1.0.0"
    end

    it "raises error when Redis is not configured" do
      expect { configuration.validate! }.to raise_error(
        ModelContextProtocol::Server::Configuration::InvalidTransportError,
        /streamable_http transport requires Redis/
      )
    end

    it "validates successfully when Redis is configured" do
      ModelContextProtocol::Server::RedisConfig.configure do |config|
        config.redis_url = "redis://localhost:6379/15"
      end

      expect { configuration.validate! }.not_to raise_error
    end
  end

  describe "allows stdout logger" do
    after do
      ModelContextProtocol::Server::GlobalConfig::ServerLogging.reset!
    end

    it "allows stdout logger for streamable_http transport" do
      ModelContextProtocol::Server.configure_redis do |config|
        config.redis_url = "redis://localhost:6379"
      end

      ModelContextProtocol::Server.configure_server_logging do |config|
        config.logdev = $stdout
      end

      config = described_class.new
      config.name = "test-server"
      config.version = "1.0.0"
      config.registry = registry

      expect { config.validate! }.not_to raise_error
    end
  end
end
