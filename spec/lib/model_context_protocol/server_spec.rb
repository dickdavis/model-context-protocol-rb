require "spec_helper"

RSpec.describe ModelContextProtocol::Server do
  describe ".initialize" do
    it "raises an error for unknown transport types" do
      server = ModelContextProtocol::Server.new do |config|
        config.name = "MCP Development Server"
        config.version = "1.0.0"
        config.registry = ModelContextProtocol::Server::Registry.new
        config.transport = :unknown_transport
      end

      expect do
        server.start
      end.to raise_error(
        ModelContextProtocol::Server::Configuration::InvalidTransportError,
        "Unknown transport type: unknown_transport"
      )
    end
  end

  describe ".start" do
    it "raises an error for an invalid configuration" do
      expect do
        server = ModelContextProtocol::Server.new do |config|
          config.version = "1.0.0"
          config.registry = ModelContextProtocol::Server::Registry.new
        end
        server.start
      end.to raise_error(ModelContextProtocol::Server::Configuration::InvalidServerNameError)
    end

    it "begins the StdioTransport" do
      transport = instance_double(ModelContextProtocol::Server::StdioTransport)
      allow(ModelContextProtocol::Server::StdioTransport).to receive(:new).and_return(transport)
      allow(transport).to receive(:handle)

      server = ModelContextProtocol::Server.new do |config|
        config.name = "MCP Development Server"
        config.version = "1.0.0"
        config.registry = ModelContextProtocol::Server::Registry.new
      end
      server.start

      expect(transport).to have_received(:handle)
    end

    it "raises error for streamable_http transport (must use Server.setup/serve)" do
      ModelContextProtocol::Server::RedisConfig.configure do |config|
        config.redis_url = "redis://localhost:6379/15"
      end

      server = ModelContextProtocol::Server.new do |config|
        config.name = "MCP Development Server"
        config.version = "1.0.0"
        config.registry = ModelContextProtocol::Server::Registry.new
        config.transport = {
          type: :streamable_http
        }
      end

      expect { server.start }.to raise_error(
        ArgumentError,
        /Use Server.setup and Server.serve for streamable_http transport/
      )
    end
  end

  describe ".configure_redis" do
    it "delegates to RedisConfig.configure" do
      expect(ModelContextProtocol::Server::RedisConfig).to receive(:configure)

      described_class.configure_redis do |config|
        config.redis_url = "redis://test:6379"
      end
    end

    it "passes the block to RedisConfig.configure" do
      block_executed = false

      allow(ModelContextProtocol::Server::RedisConfig).to receive(:configure) do |&block|
        config = double("config")
        allow(config).to receive(:redis_url=)
        block&.call(config)
        block_executed = true
      end

      described_class.configure_redis do |config|
        config.redis_url = "redis://test:6379"
      end

      expect(block_executed).to be true
    end
  end

  describe ".configure_server_logging" do
    it "delegates to GlobalConfig::ServerLogging.configure" do
      expect(ModelContextProtocol::Server::GlobalConfig::ServerLogging).to receive(:configure)

      described_class.configure_server_logging do |config|
        config.level = Logger::DEBUG
        config.progname = "TestServer"
      end
    end

    it "passes the block to GlobalConfig::ServerLogging.configure" do
      block_executed = false

      allow(ModelContextProtocol::Server::GlobalConfig::ServerLogging).to receive(:configure) do |&block|
        config = double("config")
        allow(config).to receive(:level=)
        allow(config).to receive(:progname=)
        block&.call(config)
        block_executed = true
      end

      described_class.configure_server_logging do |config|
        config.level = Logger::DEBUG
        config.progname = "TestServer"
      end

      expect(block_executed).to be true
    end
  end

  describe "singleton lifecycle management" do
    let(:registry) { ModelContextProtocol::Server::Registry.new }
    let(:mock_redis) { MockRedis.new }

    before(:each) do
      # Ensure clean state before each test
      described_class.reset!

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
      described_class.reset!
    end

    describe ".setup" do
      it "configures singleton with block configuration (does not create transport)" do
        reg = registry
        described_class.setup do |config|
          config.name = "Singleton Test Server"
          config.version = "1.0.0"
          config.registry = reg
          config.transport = {type: :streamable_http}
        end

        aggregate_failures do
          expect(described_class.configured?).to be true
          expect(described_class.running?).to be false
          expect(described_class.singleton_transport).to be_nil
          expect(described_class.singleton_configuration.name).to eq("Singleton Test Server")
          expect(described_class.singleton_router).to be_a(ModelContextProtocol::Server::Router)
        end
      end

      it "configures singleton with pre-built configuration" do
        config = ModelContextProtocol::Server::Configuration.new
        config.name = "Pre-built Server"
        config.version = "2.0.0"
        config.registry = registry
        config.transport = {type: :streamable_http}

        described_class.setup(config)

        aggregate_failures do
          expect(described_class.configured?).to be true
          expect(described_class.running?).to be false
          expect(described_class.singleton_configuration.name).to eq("Pre-built Server")
        end
      end

      it "raises error when called twice without shutdown" do
        reg = registry
        described_class.setup do |config|
          config.name = "First Setup"
          config.version = "1.0.0"
          config.registry = reg
          config.transport = {type: :streamable_http}
        end

        expect {
          described_class.setup do |config|
            config.name = "Second Setup"
            config.version = "1.0.0"
            config.registry = reg
            config.transport = {type: :streamable_http}
          end
        }.to raise_error(RuntimeError, /already configured/)
      end

      it "raises error when neither configuration nor block provided" do
        expect {
          described_class.setup
        }.to raise_error(ArgumentError, /Configuration or block required/)
      end

      it "validates configuration" do
        expect {
          described_class.setup do |config|
            # Missing required name
            config.version = "1.0.0"
            config.registry = registry
            config.transport = {type: :streamable_http}
          end
        }.to raise_error(ModelContextProtocol::Server::Configuration::InvalidServerNameError)
      end
    end

    describe ".start" do
      it "creates singleton transport after setup" do
        reg = registry
        described_class.setup do |config|
          config.name = "Start Test Server"
          config.version = "1.0.0"
          config.registry = reg
          config.transport = {type: :streamable_http}
        end

        described_class.start

        aggregate_failures do
          expect(described_class.configured?).to be true
          expect(described_class.running?).to be true
          expect(described_class.singleton_transport).to be_a(ModelContextProtocol::Server::StreamableHttpTransport)
        end
      end

      it "raises error when called without setup" do
        expect {
          described_class.start
        }.to raise_error(RuntimeError, /not configured.*Call Server\.setup first/)
      end

      it "raises error when called twice without shutdown" do
        reg = registry
        described_class.setup do |config|
          config.name = "Double Start Test"
          config.version = "1.0.0"
          config.registry = reg
          config.transport = {type: :streamable_http}
        end

        described_class.start

        expect {
          described_class.start
        }.to raise_error(RuntimeError, /already running/)
      end
    end

    describe ".serve" do
      let(:rack_env) do
        {
          "REQUEST_METHOD" => "POST",
          "PATH_INFO" => "/mcp",
          "rack.input" => StringIO.new({"method" => "initialize", "id" => "init-1", "params" => {}}.to_json),
          "CONTENT_TYPE" => "application/json",
          "HTTP_ACCEPT" => "application/json"
        }
      end

      before do
        reg = registry
        described_class.setup do |config|
          config.name = "Serve Test Server"
          config.version = "1.0.0"
          config.registry = reg
          config.transport = {type: :streamable_http, validate_origin: false}
        end
        described_class.start
      end

      it "handles requests through singleton transport" do
        result = described_class.serve(env: rack_env)

        aggregate_failures do
          expect(result[:status]).to eq(200)
          expect(result[:json][:result][:serverInfo][:name]).to eq("Serve Test Server")
        end
      end

      it "passes session_context to transport" do
        result = described_class.serve(
          env: rack_env,
          session_context: {user_id: "test-user-123"}
        )

        expect(result[:status]).to eq(200)
      end

      it "raises error when server not running" do
        described_class.shutdown

        expect {
          described_class.serve(env: rack_env)
        }.to raise_error(RuntimeError, /not running.*Call Server\.start first/)
      end

      it "raises error when only configured but not started" do
        described_class.shutdown

        reg = registry
        described_class.setup do |config|
          config.name = "Setup Only Server"
          config.version = "1.0.0"
          config.registry = reg
          config.transport = {type: :streamable_http, validate_origin: false}
        end

        expect {
          described_class.serve(env: rack_env)
        }.to raise_error(RuntimeError, /not running.*Call Server\.start first/)
      end
    end

    describe ".shutdown" do
      it "cleans up singleton state after setup and start" do
        reg = registry
        described_class.setup do |config|
          config.name = "Shutdown Test"
          config.version = "1.0.0"
          config.registry = reg
          config.transport = {type: :streamable_http}
        end
        described_class.start

        aggregate_failures do
          expect(described_class.configured?).to be true
          expect(described_class.running?).to be true
        end

        described_class.shutdown

        aggregate_failures do
          expect(described_class.configured?).to be false
          expect(described_class.running?).to be false
          expect(described_class.singleton_transport).to be_nil
          expect(described_class.singleton_router).to be_nil
          expect(described_class.singleton_configuration).to be_nil
        end
      end

      it "cleans up singleton state after setup only (no start)" do
        reg = registry
        described_class.setup do |config|
          config.name = "Shutdown After Setup Only"
          config.version = "1.0.0"
          config.registry = reg
          config.transport = {type: :streamable_http}
        end

        expect(described_class.configured?).to be true
        expect(described_class.running?).to be false

        described_class.shutdown

        aggregate_failures do
          expect(described_class.configured?).to be false
          expect(described_class.running?).to be false
        end
      end

      it "allows setup to be called again after shutdown" do
        reg = registry
        described_class.setup do |config|
          config.name = "First Server"
          config.version = "1.0.0"
          config.registry = reg
          config.transport = {type: :streamable_http}
        end
        described_class.start

        described_class.shutdown

        expect {
          described_class.setup do |config|
            config.name = "Second Server"
            config.version = "2.0.0"
            config.registry = reg
            config.transport = {type: :streamable_http}
          end
        }.not_to raise_error

        expect(described_class.singleton_configuration.name).to eq("Second Server")
      end

      it "is safe to call when not initialized" do
        expect { described_class.shutdown }.not_to raise_error
      end
    end

    describe ".configured?" do
      it "returns false when not configured" do
        expect(described_class.configured?).to be false
      end

      it "returns true after setup" do
        reg = registry
        described_class.setup do |config|
          config.name = "Config Check Server"
          config.version = "1.0.0"
          config.registry = reg
          config.transport = {type: :streamable_http}
        end

        expect(described_class.configured?).to be true
      end

      it "returns false after shutdown" do
        reg = registry
        described_class.setup do |config|
          config.name = "Config Check Server"
          config.version = "1.0.0"
          config.registry = reg
          config.transport = {type: :streamable_http}
        end
        described_class.start
        described_class.shutdown

        expect(described_class.configured?).to be false
      end
    end

    describe ".running?" do
      it "returns false when not configured" do
        expect(described_class.running?).to be false
      end

      it "returns false after setup but before start" do
        reg = registry
        described_class.setup do |config|
          config.name = "Running Check Server"
          config.version = "1.0.0"
          config.registry = reg
          config.transport = {type: :streamable_http}
        end

        expect(described_class.running?).to be false
      end

      it "returns true after start" do
        reg = registry
        described_class.setup do |config|
          config.name = "Running Check Server"
          config.version = "1.0.0"
          config.registry = reg
          config.transport = {type: :streamable_http}
        end
        described_class.start

        expect(described_class.running?).to be true
      end

      it "returns false after shutdown" do
        reg = registry
        described_class.setup do |config|
          config.name = "Running Check Server"
          config.version = "1.0.0"
          config.registry = reg
          config.transport = {type: :streamable_http}
        end
        described_class.start
        described_class.shutdown

        expect(described_class.running?).to be false
      end
    end

    describe ".reset!" do
      it "is an alias for shutdown" do
        reg = registry
        described_class.setup do |config|
          config.name = "Reset Test"
          config.version = "1.0.0"
          config.registry = reg
          config.transport = {type: :streamable_http}
        end
        described_class.start

        described_class.reset!

        aggregate_failures do
          expect(described_class.configured?).to be false
          expect(described_class.running?).to be false
        end
      end
    end
  end
end
