require "spec_helper"

RSpec.describe ModelContextProtocol::Server do
  describe "router mapping" do
    context "completion/complete" do
      it "raises an error when an invalid ref/type is provided" do
        registry = ModelContextProtocol::Server::Registry.new do
          prompts do
            register TestPrompt
          end

          resource_templates do
            register TestResourceTemplate
          end
        end

        server = described_class.new do |config|
          config.name = "Test Server"
          config.version = "1.0.0"
          config.registry = registry
        end

        message = {
          "method" => "completion/complete",
          "params" => {
            "ref" => {
              "type" => "ref/invalid_type",
              "name" => "foo"
            },
            "argument" => {
              "name" => "bar",
              "value" => "baz"
            }
          }
        }

        expect {
          server.router.route(message)
        }.to raise_error(ModelContextProtocol::Server::ParameterValidationError, "ref/type invalid")
      end

      context "for prompts" do
        it "returns a completion for the given prompt" do
          registry = ModelContextProtocol::Server::Registry.new do
            prompts do
              register TestPrompt
            end
          end

          server = described_class.new do |config|
            config.name = "Test Server"
            config.version = "1.0.0"
            config.registry = registry
          end

          message = {
            "method" => "completion/complete",
            "params" => {
              "ref" => {
                "type" => "ref/prompt",
                "name" => "test_prompt"
              },
              "argument" => {
                "name" => "message",
                "value" => "f"
              }
            }
          }

          response = server.router.route(message)

          expect(response.serialized).to eq(
            completion: {
              values: ["foo"],
              total: 1,
              hasMore: false
            }
          )
        end

        it "returns a null completion when no matching prompt is found" do
          registry = ModelContextProtocol::Server::Registry.new do
            prompts do
              register TestPrompt
            end
          end

          server = described_class.new do |config|
            config.name = "Test Server"
            config.version = "1.0.0"
            config.registry = registry
          end

          message = {
            "method" => "completion/complete",
            "params" => {
              "ref" => {
                "type" => "ref/prompt",
                "name" => "foo"
              },
              "argument" => {
                "name" => "bar",
                "value" => "baz"
              }
            }
          }

          response = server.router.route(message)

          expect(response.serialized).to eq(
            completion: {
              values: [],
              total: 0,
              hasMore: false
            }
          )
        end
      end

      context "for resource templates" do
        it "looks up resource templates when direct resource is not found" do
          registry = ModelContextProtocol::Server::Registry.new do
            resource_templates do
              register TestResourceTemplate
            end
          end

          server = described_class.new do |config|
            config.name = "Test Server"
            config.version = "1.0.0"
            config.registry = registry
          end

          message = {
            "method" => "completion/complete",
            "params" => {
              "ref" => {
                "type" => "ref/resource",
                "uri" => "resource:///{name}"
              },
              "argument" => {
                "name" => "name",
                "value" => "te"
              }
            }
          }

          response = server.router.route(message)

          expect(response.serialized).to eq(
            completion: {
              values: ["test-resource"],
              total: 1,
              hasMore: false
            }
          )
        end

        it "returns a null completion when no matching resource template is found" do
          registry = ModelContextProtocol::Server::Registry.new do
            resource_templates do
              register TestResourceTemplate
            end
          end

          server = described_class.new do |config|
            config.name = "Test Server"
            config.version = "1.0.0"
            config.registry = registry
          end

          message = {
            "method" => "completion/complete",
            "params" => {
              "ref" => {
                "type" => "ref/resource",
                "uri" => "not-valid"
              },
              "argument" => {
                "name" => "bar",
                "value" => "baz"
              }
            }
          }

          response = server.router.route(message)

          expect(response.serialized).to eq(
            completion: {
              values: [],
              total: 0,
              hasMore: false
            }
          )
        end
      end
    end

    context "resources/read" do
      it "looks up resource templates when direct resource is not found" do
        registry = ModelContextProtocol::Server::Registry.new do
          resource_templates do
            register TestResourceTemplate
          end
        end

        server = described_class.new do |config|
          config.name = "Test Server"
          config.version = "1.0.0"
          config.registry = registry
        end

        test_uri = "resource:///{name}"
        message = {"method" => "resources/read", "params" => {"uri" => test_uri}}
        response = server.router.route(message)

        expect(response.serialized).to eq(
          contents: [
            {
              mimeType: "text/plain",
              text: "Here's the resource name you requested: test-template",
              uri: test_uri
            }
          ]
        )
      end

      it "returns nil when no matching resource or template is found" do
        registry = ModelContextProtocol::Server::Registry.new
        server = described_class.new do |config|
          config.name = "Test Server"
          config.version = "1.0.0"
          config.registry = registry
        end

        test_uri = "null://nonexistent"
        message = {"method" => "resources/read", "params" => {"uri" => test_uri}}
        response = server.router.route(message)

        expect(response).to be_nil
      end
    end

    context "resources/templates/list" do
      it "returns a list of registered resource templates" do
        # Set up a registry with resource templates
        registry = ModelContextProtocol::Server::Registry.new do
          resource_templates do
            register TestResourceTemplate
          end
        end

        server = described_class.new do |config|
          config.name = "Test Server"
          config.version = "1.0.0"
          config.registry = registry
        end

        message = {"method" => "resources/templates/list"}
        response = server.router.route(message)
        expect(response.serialized).to eq(
          resourceTemplates: [
            {
              name: "Test Resource Template",
              description: "A test resource template",
              mimeType: "text/plain",
              uriTemplate: "resource:///{name}"
            }
          ]
        )
      end
    end
  end

  describe ".start" do
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
