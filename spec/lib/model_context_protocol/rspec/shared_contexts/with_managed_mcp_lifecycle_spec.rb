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
  end

  after(:each) do
    ModelContextProtocol::Server.reset!
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

      ModelContextProtocol::Server.start

      expect(server.running?).to be true

      ModelContextProtocol::Server.shutdown
    end

    it "shuts down the transport after the example" do
      ModelContextProtocol::Server.start

      expect(ModelContextProtocol::Server.running?).to be true

      ModelContextProtocol::Server.shutdown

      expect(ModelContextProtocol::Server.running?).to be false
    end

    it "preserves Server.instance after shutdown" do
      ModelContextProtocol::Server.start
      ModelContextProtocol::Server.shutdown

      expect(ModelContextProtocol::Server.instance).not_to be_nil
      expect(ModelContextProtocol::Server.configured?).to be true
    end
  end
end
