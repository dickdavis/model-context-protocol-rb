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
                "name" => "brainstorm_excuses"
              },
              "argument" => {
                "name" => "tone",
                "value" => "w"
              }
            }
          }

          response = server.router.route(message)

          expect(response.serialized).to eq(
            completion: {
              values: ["whiny"],
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
                "uri" => "file:///{name}"
              },
              "argument" => {
                "name" => "name",
                "value" => "to"
              }
            }
          }

          response = server.router.route(message)

          expect(response.serialized).to eq(
            completion: {
              values: ["top-secret-plans.txt"],
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
      it "raises an error when resource is not found" do
        registry = ModelContextProtocol::Server::Registry.new do
          resources do
            register TestResource
          end
        end

        server = described_class.new do |config|
          config.name = "Test Server"
          config.version = "1.0.0"
          config.registry = registry
        end

        test_uri = "resource:///invalid"
        message = {"method" => "resources/read", "params" => {"uri" => test_uri}}

        expect {
          server.router.route(message)
        }.to raise_error(ModelContextProtocol::Server::ParameterValidationError, "resource not found for #{test_uri}")
      end

      it "returns the serialized resource data when the resource is found" do
        registry = ModelContextProtocol::Server::Registry.new do
          resources do
            register TestResource
          end
        end

        server = described_class.new do |config|
          config.name = "Test Server"
          config.version = "1.0.0"
          config.registry = registry
        end

        test_uri = "file:///top-secret-plans.txt"
        message = {"method" => "resources/read", "params" => {"uri" => test_uri}}

        response = server.router.route(message)

        expect(response.serialized).to eq(
          contents: [
            {
              mimeType: "text/plain",
              text: "Nothing to see here, move along.",
              uri: "file:///top-secret-plans.txt"
            }
          ]
        )
      end
    end

    context "resources/templates/list" do
      it "returns a list of registered resource templates" do
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
              name: "project-document-resource-template",
              description: "A resource template for retrieving project documents",
              mimeType: "text/plain",
              uriTemplate: "file:///{name}"
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
        config.logging_enabled = true
        config.registry = ModelContextProtocol::Server::Registry.new
      end
      server.start

      expect(transport).to have_received(:handle)
    end

    it "handles StreamableHttpTransport requests" do
      mock_redis = MockRedis.new
      allow(mock_redis).to receive(:publish)
      allow(mock_redis).to receive(:subscribe)

      transport = instance_double(ModelContextProtocol::Server::StreamableHttpTransport)
      allow(ModelContextProtocol::Server::StreamableHttpTransport).to receive(:new).and_return(transport)
      allow(transport).to receive(:handle).and_return({json: {success: true}, status: 200})

      server = ModelContextProtocol::Server.new do |config|
        config.name = "MCP Development Server"
        config.version = "1.0.0"
        config.logging_enabled = true
        config.registry = ModelContextProtocol::Server::Registry.new
        config.transport = {
          type: :streamable_http,
          redis_client: mock_redis
        }
      end

      result = server.start

      expect(transport).to have_received(:handle)
      expect(result).to eq({json: {success: true}, status: 200})
    end

    it "raises an error for unknown transport types" do
      server = ModelContextProtocol::Server.new do |config|
        config.name = "MCP Development Server"
        config.version = "1.0.0"
        config.logging_enabled = true
        config.registry = ModelContextProtocol::Server::Registry.new
        config.transport = :unknown_transport
      end

      expect { server.start }.to raise_error(
        ModelContextProtocol::Server::Configuration::InvalidTransportError,
        "Unknown transport type: unknown_transport"
      )
    end

    context "logging/setLevel handler" do
      it "sets the log level when valid" do
        server = described_class.new do |config|
          config.name = "Test Server"
          config.version = "1.0.0"
          config.registry = ModelContextProtocol::Server::Registry.new
        end

        message = {
          "method" => "logging/setLevel",
          "params" => {"level" => "debug"}
        }

        expect(server.configuration.logger).to receive(:set_mcp_level).with("debug")
        response = server.router.route(message)
        expect(response.serialized).to eq({})
      end

      it "raises error for invalid log level" do
        server = described_class.new do |config|
          config.name = "Test Server"
          config.version = "1.0.0"
          config.registry = ModelContextProtocol::Server::Registry.new
        end

        message = {
          "method" => "logging/setLevel",
          "params" => {"level" => "invalid"}
        }

        expect {
          server.router.route(message)
        }.to raise_error(ModelContextProtocol::Server::ParameterValidationError, /Invalid log level: invalid/)
      end
    end
  end
end
