require "spec_helper"
require "model_context_protocol/rspec"

RSpec.describe "with managed mcp lifecycle" do
  let(:mock_redis) { MockRedis.new }

  before(:each) do
    allow(Thread).to receive(:new).and_return(double("thread", alive?: false, kill: nil, join: nil, "name=": nil))

    manager = ModelContextProtocol::Server::RedisConfig.instance.manager
    manager&.instance_variable_set(:@reaper_thread, nil)

    ModelContextProtocol::Server.reset!
    ModelContextProtocol::Server::RedisConfig.reset!
    ModelContextProtocol::Server::GlobalConfig::ServerLogging.reset!
  end

  after(:each) do
    ModelContextProtocol::Server.reset!
    ModelContextProtocol::Server::GlobalConfig::ServerLogging.reset!
  end

  context "when the server is configured" do
    before(:each) do
      ModelContextProtocol::Server.with_streamable_http_transport do |config|
        config.name = "Lifecycle Test Server"
        config.version = "1.0.0"
        config.registry {}
        config.redis_url = "redis://localhost:6379/15"
      end

      allow(ModelContextProtocol::Server::RedisConfig.pool).to receive(:checkout).and_return(mock_redis)
      allow(ModelContextProtocol::Server::RedisConfig.pool).to receive(:checkin)
    end

    it "starts the transport before the example" do
      server = ModelContextProtocol::Server.instance
      expect(server.running?).to be false

      # Simulate what the shared context does
      ModelContextProtocol::Server.configure_server_logging do |config|
        config.logdev = File::NULL
      end
      ModelContextProtocol::Server.start

      expect(server.running?).to be true

      ModelContextProtocol::Server.shutdown
      ModelContextProtocol::Server::GlobalConfig::ServerLogging.reset!
    end

    it "shuts down the transport after the example" do
      ModelContextProtocol::Server.configure_server_logging do |config|
        config.logdev = File::NULL
      end
      ModelContextProtocol::Server.start

      expect(ModelContextProtocol::Server.running?).to be true

      ModelContextProtocol::Server.shutdown

      expect(ModelContextProtocol::Server.running?).to be false

      ModelContextProtocol::Server::GlobalConfig::ServerLogging.reset!
    end

    it "preserves Server.instance after shutdown" do
      ModelContextProtocol::Server.configure_server_logging do |config|
        config.logdev = File::NULL
      end
      ModelContextProtocol::Server.start
      ModelContextProtocol::Server.shutdown

      expect(ModelContextProtocol::Server.instance).not_to be_nil
      expect(ModelContextProtocol::Server.configured?).to be true

      ModelContextProtocol::Server::GlobalConfig::ServerLogging.reset!
    end

    it "suppresses server logging during the example" do
      ModelContextProtocol::Server.configure_server_logging do |config|
        config.logdev = File::NULL
      end

      expect(ModelContextProtocol::Server::GlobalConfig::ServerLogging.configured?).to be true
      params = ModelContextProtocol::Server::GlobalConfig::ServerLogging.logger_params
      expect(params[:logdev]).to eq(File::NULL)

      ModelContextProtocol::Server::GlobalConfig::ServerLogging.reset!
    end

    it "resets ServerLogging after the example" do
      ModelContextProtocol::Server.configure_server_logging do |config|
        config.logdev = File::NULL
      end

      expect(ModelContextProtocol::Server::GlobalConfig::ServerLogging.configured?).to be true

      ModelContextProtocol::Server::GlobalConfig::ServerLogging.reset!

      expect(ModelContextProtocol::Server::GlobalConfig::ServerLogging.configured?).to be false
    end
  end
end
