require "spec_helper"

RSpec.describe ModelContextProtocol::Server do
  let(:registry) { ModelContextProtocol::Server::Registry.new }
  let(:mock_redis) { MockRedis.new }

  before(:each) do
    described_class.reset!
  end

  after(:each) do
    described_class.reset!
  end

  describe ".with_stdio_transport" do
    it "creates a server with StdioConfiguration" do
      server = described_class.with_stdio_transport do |config|
        config.name = "Stdio Server"
        config.version = "1.0.0"
        config.registry = registry
      end

      aggregate_failures do
        expect(server).to be_a(described_class)
        expect(server.configuration).to be_a(ModelContextProtocol::Server::StdioConfiguration)
        expect(server.configuration.transport_type).to eq(:stdio)
        expect(server.router).to be_a(ModelContextProtocol::Server::Router)
      end
    end

    it "auto-sets Server.instance" do
      server = described_class.with_stdio_transport do |config|
        config.name = "Stdio Server"
        config.version = "1.0.0"
        config.registry = registry
      end

      expect(described_class.instance).to eq(server)
    end

    it "validates the configuration" do
      expect {
        described_class.with_stdio_transport do |config|
          # Missing required name
          config.version = "1.0.0"
          config.registry = registry
        end
      }.to raise_error(ModelContextProtocol::Server::Configuration::InvalidServerNameError)
    end
  end

  describe ".with_streamable_http_transport" do
    before(:each) do
      ModelContextProtocol::Server::RedisConfig.configure do |config|
        config.redis_url = "redis://localhost:6379/15"
      end
    end

    it "creates a server with StreamableHttpConfiguration" do
      server = described_class.with_streamable_http_transport do |config|
        config.name = "HTTP Server"
        config.version = "1.0.0"
        config.registry = registry
      end

      aggregate_failures do
        expect(server).to be_a(described_class)
        expect(server.configuration).to be_a(ModelContextProtocol::Server::StreamableHttpConfiguration)
        expect(server.configuration.transport_type).to eq(:streamable_http)
      end
    end

    it "auto-sets Server.instance" do
      server = described_class.with_streamable_http_transport do |config|
        config.name = "HTTP Server"
        config.version = "1.0.0"
        config.registry = registry
      end

      expect(described_class.instance).to eq(server)
    end

    it "supports transport-specific configuration" do
      server = described_class.with_streamable_http_transport do |config|
        config.name = "HTTP Server"
        config.version = "1.0.0"
        config.registry = registry
        config.require_sessions = true
        config.session_ttl = 7200
        config.allowed_origins = ["*"]
      end

      aggregate_failures do
        expect(server.configuration.require_sessions).to eq(true)
        expect(server.configuration.session_ttl).to eq(7200)
        expect(server.configuration.allowed_origins).to eq(["*"])
      end
    end

    it "validates the configuration" do
      expect {
        described_class.with_streamable_http_transport do |config|
          config.version = "1.0.0"
          config.registry = registry
        end
      }.to raise_error(ModelContextProtocol::Server::Configuration::InvalidServerNameError)
    end
  end

  describe "#start" do
    context "with stdio transport" do
      it "creates StdioTransport and calls handle" do
        transport = instance_double(ModelContextProtocol::Server::StdioTransport)
        allow(ModelContextProtocol::Server::StdioTransport).to receive(:new).and_return(transport)
        allow(transport).to receive(:handle)

        server = described_class.with_stdio_transport do |config|
          config.name = "Stdio Server"
          config.version = "1.0.0"
          config.registry = registry
        end
        server.start

        expect(transport).to have_received(:handle)
      end
    end

    context "with streamable_http transport" do
      before(:each) do
        ModelContextProtocol::Server::RedisConfig.configure do |config|
          config.redis_url = "redis://localhost:6379/15"
        end
        allow(ModelContextProtocol::Server::RedisConfig.pool).to receive(:checkout).and_return(mock_redis)
        allow(ModelContextProtocol::Server::RedisConfig.pool).to receive(:checkin)
        allow(Thread).to receive(:new).and_return(double("thread", alive?: false, kill: nil, join: nil, "name=": nil))
      end

      it "creates StreamableHttpTransport" do
        server = described_class.with_streamable_http_transport do |config|
          config.name = "HTTP Server"
          config.version = "1.0.0"
          config.registry = registry
        end
        server.start

        aggregate_failures do
          expect(server.running?).to be true
          expect(server.transport).to be_a(ModelContextProtocol::Server::StreamableHttpTransport)
        end
      end

      it "raises error when already running" do
        server = described_class.with_streamable_http_transport do |config|
          config.name = "HTTP Server"
          config.version = "1.0.0"
          config.registry = registry
        end
        server.start

        expect { server.start }.to raise_error(RuntimeError, /already running/)
      end
    end
  end

  describe "#serve" do
    let(:rack_env) do
      {
        "REQUEST_METHOD" => "POST",
        "PATH_INFO" => "/mcp",
        "rack.input" => StringIO.new({"method" => "initialize", "id" => "init-1", "params" => {}}.to_json),
        "CONTENT_TYPE" => "application/json",
        "HTTP_ACCEPT" => "application/json"
      }
    end

    before(:each) do
      ModelContextProtocol::Server::RedisConfig.configure do |config|
        config.redis_url = "redis://localhost:6379/15"
      end
      allow(ModelContextProtocol::Server::RedisConfig.pool).to receive(:checkout).and_return(mock_redis)
      allow(ModelContextProtocol::Server::RedisConfig.pool).to receive(:checkin)
      allow(Thread).to receive(:new).and_return(double("thread", alive?: false, kill: nil, join: nil, "name=": nil))
    end

    it "handles requests through transport" do
      server = described_class.with_streamable_http_transport do |config|
        config.name = "Serve Test Server"
        config.version = "1.0.0"
        config.registry = registry
        config.validate_origin = false
      end
      server.start

      result = server.serve(env: rack_env)

      aggregate_failures do
        expect(result[:status]).to eq(200)
        expect(result[:json][:result][:serverInfo][:name]).to eq("Serve Test Server")
      end
    end

    it "passes session_context to transport" do
      server = described_class.with_streamable_http_transport do |config|
        config.name = "Serve Test Server"
        config.version = "1.0.0"
        config.registry = registry
        config.validate_origin = false
      end
      server.start

      result = server.serve(env: rack_env, session_context: {user_id: "test-user-123"})
      expect(result[:status]).to eq(200)
    end

    it "raises error when server not running" do
      server = described_class.with_streamable_http_transport do |config|
        config.name = "Serve Test Server"
        config.version = "1.0.0"
        config.registry = registry
        config.validate_origin = false
      end

      expect {
        server.serve(env: rack_env)
      }.to raise_error(RuntimeError, /not running.*Call start first/)
    end
  end

  describe "#shutdown" do
    before(:each) do
      ModelContextProtocol::Server::RedisConfig.configure do |config|
        config.redis_url = "redis://localhost:6379/15"
      end
      allow(ModelContextProtocol::Server::RedisConfig.pool).to receive(:checkout).and_return(mock_redis)
      allow(ModelContextProtocol::Server::RedisConfig.pool).to receive(:checkin)
      allow(Thread).to receive(:new).and_return(double("thread", alive?: false, kill: nil, join: nil, "name=": nil))
    end

    it "clears the transport" do
      server = described_class.with_streamable_http_transport do |config|
        config.name = "Shutdown Test"
        config.version = "1.0.0"
        config.registry = registry
      end
      server.start

      expect(server.running?).to be true

      server.shutdown

      expect(server.running?).to be false
    end

    it "is safe to call when not running" do
      server = described_class.with_streamable_http_transport do |config|
        config.name = "Shutdown Test"
        config.version = "1.0.0"
        config.registry = registry
      end

      expect { server.shutdown }.not_to raise_error
    end
  end

  describe "#configured?" do
    it "returns true for a built server" do
      server = described_class.with_stdio_transport do |config|
        config.name = "Test"
        config.version = "1.0.0"
        config.registry = registry
      end

      expect(server.configured?).to be true
    end
  end

  describe "#running?" do
    it "returns false before start" do
      server = described_class.with_stdio_transport do |config|
        config.name = "Test"
        config.version = "1.0.0"
        config.registry = registry
      end

      expect(server.running?).to be false
    end
  end

  describe ".reset!" do
    before(:each) do
      ModelContextProtocol::Server::RedisConfig.configure do |config|
        config.redis_url = "redis://localhost:6379/15"
      end
      allow(ModelContextProtocol::Server::RedisConfig.pool).to receive(:checkout).and_return(mock_redis)
      allow(ModelContextProtocol::Server::RedisConfig.pool).to receive(:checkin)
      allow(Thread).to receive(:new).and_return(double("thread", alive?: false, kill: nil, join: nil, "name=": nil))
    end

    it "clears the instance" do
      described_class.with_streamable_http_transport do |config|
        config.name = "Reset Test"
        config.version = "1.0.0"
        config.registry = registry
      end

      expect(described_class.instance).not_to be_nil

      described_class.reset!

      aggregate_failures do
        expect(described_class.instance).to be_nil
        expect(described_class.configured?).to be false
        expect(described_class.running?).to be false
      end
    end
  end

  describe "class-level delegations" do
    before(:each) do
      ModelContextProtocol::Server::RedisConfig.configure do |config|
        config.redis_url = "redis://localhost:6379/15"
      end
      allow(ModelContextProtocol::Server::RedisConfig.pool).to receive(:checkout).and_return(mock_redis)
      allow(ModelContextProtocol::Server::RedisConfig.pool).to receive(:checkin)
      allow(Thread).to receive(:new).and_return(double("thread", alive?: false, kill: nil, join: nil, "name=": nil))
    end

    it "delegates configured? to instance" do
      expect(described_class.configured?).to be false

      described_class.with_streamable_http_transport do |config|
        config.name = "Delegation Test"
        config.version = "1.0.0"
        config.registry = registry
      end

      expect(described_class.configured?).to be true
    end

    it "delegates running? to instance" do
      expect(described_class.running?).to be false

      described_class.with_streamable_http_transport do |config|
        config.name = "Delegation Test"
        config.version = "1.0.0"
        config.registry = registry
      end
      described_class.start

      expect(described_class.running?).to be true
    end

    it "delegates start to instance" do
      described_class.with_streamable_http_transport do |config|
        config.name = "Delegation Test"
        config.version = "1.0.0"
        config.registry = registry
      end
      described_class.start

      expect(described_class.instance.running?).to be true
    end

    it "raises NotConfiguredError when starting without a configured instance" do
      expect {
        described_class.start
      }.to raise_error(ModelContextProtocol::Server::NotConfiguredError, /Server not configured/)
    end

    it "delegates serve to instance" do
      rack_env = {
        "REQUEST_METHOD" => "POST",
        "PATH_INFO" => "/mcp",
        "rack.input" => StringIO.new({"method" => "initialize", "id" => "init-1", "params" => {}}.to_json),
        "CONTENT_TYPE" => "application/json",
        "HTTP_ACCEPT" => "application/json"
      }

      described_class.with_streamable_http_transport do |config|
        config.name = "Delegation Test"
        config.version = "1.0.0"
        config.registry = registry
        config.validate_origin = false
      end
      described_class.start

      result = described_class.serve(env: rack_env)
      expect(result[:status]).to eq(200)
    end

    it "raises NotConfiguredError when serving without a configured instance" do
      expect {
        described_class.serve(env: {})
      }.to raise_error(ModelContextProtocol::Server::NotConfiguredError, /Server not configured/)
    end

    it "delegates shutdown to instance" do
      described_class.with_streamable_http_transport do |config|
        config.name = "Delegation Test"
        config.version = "1.0.0"
        config.registry = registry
      end
      described_class.start
      described_class.shutdown

      expect(described_class.instance.running?).to be false
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
end
