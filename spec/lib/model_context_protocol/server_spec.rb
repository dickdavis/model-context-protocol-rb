require "spec_helper"

RSpec.describe ModelContextProtocol::Server do
  describe "start" do
    it "raises an error for an invalid configuration" do
      expect do
        server = ModelContextProtocol::Server.new do |config|
          config.version = "1.0.0"
          config.enable_log = true
          config.registry = ModelContextProtocol::Server::Registry.new
        end
        server.start
      end.to raise_error(ModelContextProtocol::Server::Configuration::InvalidServerNameError)
    end

    it "begins the StdioTransport" do
      transport = instance_double(ModelContextProtocol::Server::StdioTransport)
      allow(ModelContextProtocol::Server::StdioTransport).to receive(:new).and_return(transport)
      allow(transport).to receive(:begin)

      server = ModelContextProtocol::Server.new do |config|
        config.name = "MCP Development Server"
        config.version = "1.0.0"
        config.enable_log = true
        config.registry = ModelContextProtocol::Server::Registry.new
      end
      server.start

      expect(transport).to have_received(:begin)
    end

    context "when logging is not enabled" do
      it "initializes the StdioTransport logger with a null logdev" do
        transport = instance_double(ModelContextProtocol::Server::StdioTransport)
        allow(ModelContextProtocol::Server::StdioTransport).to receive(:new).and_return(transport)
        allow(transport).to receive(:begin)

        logger_class = class_double(Logger)
        allow(logger_class).to receive(:new)
        stub_const("Logger", logger_class)

        server = ModelContextProtocol::Server.new do |config|
          config.name = "MCP Development Server"
          config.version = "1.0.0"
          config.enable_log = false
          config.registry = ModelContextProtocol::Server::Registry.new
        end
        server.start

        expect(logger_class).to have_received(:new).with(File::NULL)
      end
    end

    context "when logging is enabled" do
      it "initializes the StdioTransport logger with a $stderr logdev" do
        transport = instance_double(ModelContextProtocol::Server::StdioTransport)
        allow(ModelContextProtocol::Server::StdioTransport).to receive(:new).and_return(transport)
        allow(transport).to receive(:begin)

        logger_class = class_double(Logger)
        allow(logger_class).to receive(:new)
        stub_const("Logger", logger_class)

        server = ModelContextProtocol::Server.new do |config|
          config.name = "MCP Development Server"
          config.version = "1.0.0"
          config.enable_log = true
          config.registry = ModelContextProtocol::Server::Registry.new
        end
        server.start

        expect(logger_class).to have_received(:new).with($stderr)
      end
    end
  end
end
