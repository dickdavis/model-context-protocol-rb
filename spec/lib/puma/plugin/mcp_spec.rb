require "spec_helper"
require "puma/plugin/mcp"

RSpec.describe "Puma::Plugin::MCP" do
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
    # Suppress background threads in tests
    allow(Thread).to receive(:new).and_return(double("thread", alive?: false, kill: nil, join: nil, "name=": nil))

    # Clear any stale reaper thread references before reset to avoid
    # "leaked double" errors from the previous test's Thread.new stub
    manager = ModelContextProtocol::Server::RedisConfig.instance.manager
    manager&.instance_variable_set(:@reaper_thread, nil)

    # Ensure clean state before each test
    ModelContextProtocol::Server.reset!
    ModelContextProtocol::Server::RedisConfig.reset!
  end

  after(:each) do
    ModelContextProtocol::Server.reset!
  end

  describe "#start_mcp_server" do
    it "starts the server when configured but not running" do
      ModelContextProtocol::Server.with_streamable_http_transport do |config|
        config.name = "Plugin Test Server"
        config.version = "1.0.0"
        config.registry {}
        config.redis_url = "redis://localhost:6379/15"
      end

      allow(ModelContextProtocol::Server::RedisConfig.pool).to receive(:checkout).and_return(mock_redis)
      allow(ModelContextProtocol::Server::RedisConfig.pool).to receive(:checkin)

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
      ModelContextProtocol::Server.with_streamable_http_transport do |config|
        config.name = "Already Running Server"
        config.version = "1.0.0"
        config.registry {}
        config.redis_url = "redis://localhost:6379/15"
      end

      allow(ModelContextProtocol::Server::RedisConfig.pool).to receive(:checkout).and_return(mock_redis)
      allow(ModelContextProtocol::Server::RedisConfig.pool).to receive(:checkin)

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
      ModelContextProtocol::Server.with_streamable_http_transport do |config|
        config.name = "Shutdown Test Server"
        config.version = "1.0.0"
        config.registry {}
        config.redis_url = "redis://localhost:6379/15"
      end

      allow(ModelContextProtocol::Server::RedisConfig.pool).to receive(:checkout).and_return(mock_redis)
      allow(ModelContextProtocol::Server::RedisConfig.pool).to receive(:checkin)

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
      ModelContextProtocol::Server.with_streamable_http_transport do |config|
        config.name = "Configured Only Server"
        config.version = "1.0.0"
        config.registry {}
        config.redis_url = "redis://localhost:6379/15"
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
    it "captures the DSL reference" do
      dsl = double("dsl")
      plugin_instance.config(dsl)
      expect(plugin_instance.instance_variable_get(:@dsl)).to eq(dsl)
    end
  end

  describe "#start" do
    let(:dsl) { double("dsl") }
    let(:events) { double("events") }
    let(:options) { {} }
    let(:launcher) { double("launcher", events: events, options: options) }

    before { plugin_instance.config(dsl) }

    it "registers worker hooks in clustered mode" do
      options[:workers] = 2
      expect(dsl).to receive(:before_worker_boot)
      expect(dsl).to receive(:before_worker_shutdown)
      expect(events).not_to receive(:after_booted)
      expect(events).not_to receive(:after_stopped)

      plugin_instance.start(launcher)
    end

    it "registers event hooks in single mode" do
      options[:workers] = 0
      expect(dsl).not_to receive(:before_worker_boot)
      expect(dsl).not_to receive(:before_worker_shutdown)
      expect(events).to receive(:after_booted)
      expect(events).to receive(:after_stopped)

      plugin_instance.start(launcher)
    end
  end
end
