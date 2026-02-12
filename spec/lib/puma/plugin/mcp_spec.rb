require "spec_helper"
require "puma/plugin/mcp"

RSpec.describe "Puma::Plugin::MCP" do
  let(:registry) { ModelContextProtocol::Server::Registry.new }
  let(:mock_redis) { MockRedis.new }

  # Get the plugin class created by Puma::Plugin.create
  let(:plugin_class) do
    Puma::Plugins.instance_variable_get(:@plugins)["mcp"]
  end

  # Create an instance of the plugin to test its methods
  let(:plugin_instance) do
    plugin_class.allocate
  end

  before(:each) do
    # Ensure clean state before each test
    ModelContextProtocol::Server.reset!

    # Configure Redis for streamable_http transport
    ModelContextProtocol::Server::RedisConfig.configure do |config|
      config.redis_url = "redis://localhost:6379/15"
    end

    allow(ModelContextProtocol::Server::RedisConfig.pool).to receive(:checkout).and_return(mock_redis)
    allow(ModelContextProtocol::Server::RedisConfig.pool).to receive(:checkin)

    # Suppress background threads in tests
    allow(Thread).to receive(:new).and_return(double("thread", alive?: false, kill: nil, join: nil, "name=": nil))
  end

  after(:each) do
    ModelContextProtocol::Server.reset!
  end

  describe "#start_mcp_server" do
    it "starts the server when configured but not running" do
      reg = registry
      ModelContextProtocol::Server.with_streamable_http_transport do |config|
        config.name = "Plugin Test Server"
        config.version = "1.0.0"
        config.registry = reg
      end

      expect(ModelContextProtocol::Server.configured?).to be true
      expect(ModelContextProtocol::Server.running?).to be false

      plugin_instance.send(:start_mcp_server)

      expect(ModelContextProtocol::Server.running?).to be true
    end

    it "does nothing when not configured" do
      expect(ModelContextProtocol::Server.configured?).to be false
      expect(ModelContextProtocol::Server.running?).to be false

      expect {
        plugin_instance.send(:start_mcp_server)
      }.not_to raise_error

      expect(ModelContextProtocol::Server.running?).to be false
    end

    it "does nothing when already running" do
      reg = registry
      ModelContextProtocol::Server.with_streamable_http_transport do |config|
        config.name = "Already Running Server"
        config.version = "1.0.0"
        config.registry = reg
      end
      ModelContextProtocol::Server.start

      expect(ModelContextProtocol::Server.running?).to be true

      # Should not raise an error or try to start again
      expect {
        plugin_instance.send(:start_mcp_server)
      }.not_to raise_error
    end
  end

  describe "#shutdown_mcp_server" do
    it "shuts down the server when running" do
      reg = registry
      ModelContextProtocol::Server.with_streamable_http_transport do |config|
        config.name = "Shutdown Test Server"
        config.version = "1.0.0"
        config.registry = reg
      end
      ModelContextProtocol::Server.start

      expect(ModelContextProtocol::Server.running?).to be true

      plugin_instance.send(:shutdown_mcp_server)

      expect(ModelContextProtocol::Server.running?).to be false
    end

    it "does nothing when not running" do
      expect(ModelContextProtocol::Server.running?).to be false

      expect {
        plugin_instance.send(:shutdown_mcp_server)
      }.not_to raise_error
    end

    it "does nothing when configured but not started" do
      reg = registry
      ModelContextProtocol::Server.with_streamable_http_transport do |config|
        config.name = "Configured Only Server"
        config.version = "1.0.0"
        config.registry = reg
      end

      expect(ModelContextProtocol::Server.configured?).to be true
      expect(ModelContextProtocol::Server.running?).to be false

      expect {
        plugin_instance.send(:shutdown_mcp_server)
      }.not_to raise_error

      # Should still be configured since shutdown only clears transport
      expect(ModelContextProtocol::Server.configured?).to be true
    end
  end

  describe "#config" do
    it "registers worker hooks in clustered mode" do
      dsl = double("dsl")
      allow(dsl).to receive(:get).with(:workers, 0).and_return(2)
      expect(dsl).to receive(:before_worker_boot)
      expect(dsl).to receive(:before_worker_shutdown)
      expect(dsl).not_to receive(:after_booted)
      expect(dsl).not_to receive(:after_stopped)

      plugin_instance.config(dsl)
    end

    it "registers booted hooks in single mode" do
      dsl = double("dsl")
      allow(dsl).to receive(:get).with(:workers, 0).and_return(0)
      expect(dsl).not_to receive(:before_worker_boot)
      expect(dsl).not_to receive(:before_worker_shutdown)
      expect(dsl).to receive(:after_booted)
      expect(dsl).to receive(:after_stopped)

      plugin_instance.config(dsl)
    end

    it "treats nil workers as single mode" do
      dsl = double("dsl")
      allow(dsl).to receive(:get).with(:workers, 0).and_return(nil)
      expect(dsl).not_to receive(:before_worker_boot)
      expect(dsl).not_to receive(:before_worker_shutdown)
      expect(dsl).to receive(:after_booted)
      expect(dsl).to receive(:after_stopped)

      plugin_instance.config(dsl)
    end
  end
end
