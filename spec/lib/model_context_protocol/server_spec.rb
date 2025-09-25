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

    it "handles StreamableHttpTransport requests" do
      ModelContextProtocol::Server::RedisConfig.configure do |config|
        config.redis_url = "redis://localhost:6379/15"
      end

      transport = instance_double(ModelContextProtocol::Server::StreamableHttpTransport)
      allow(ModelContextProtocol::Server::StreamableHttpTransport).to receive(:new).and_return(transport)
      allow(transport).to receive(:handle).and_return({json: {success: true}, status: 200})

      server = ModelContextProtocol::Server.new do |config|
        config.name = "MCP Development Server"
        config.version = "1.0.0"
        config.registry = ModelContextProtocol::Server::Registry.new
        config.transport = {
          type: :streamable_http
        }
      end

      result = server.start

      aggregate_failures do
        expect(transport).to have_received(:handle)
        expect(result).to eq({json: {success: true}, status: 200})
      end
    end
  end

  describe "protocol version negotiation" do
    let(:server) do
      described_class.new do |config|
        config.name = "Test Server"
        config.version = "1.0.0"
        config.registry = ModelContextProtocol::Server::Registry.new
      end
    end

    it "returns client's protocol version when supported" do
      message = {
        "method" => "initialize",
        "id" => "init-1",
        "params" => {
          "protocolVersion" => "2025-06-18"
        }
      }

      result = server.router.route(message)

      expect(result.serialized[:protocolVersion]).to eq("2025-06-18")
    end

    it "returns server's latest version when client sends unsupported version" do
      message = {
        "method" => "initialize",
        "id" => "init-1",
        "params" => {
          "protocolVersion" => "2020-01-01"
        }
      }

      result = server.router.route(message)

      expect(result.serialized[:protocolVersion]).to eq("2025-06-18")
    end

    it "returns server's latest version when no protocol version provided" do
      message = {
        "method" => "initialize",
        "id" => "init-1",
        "params" => {}
      }

      result = server.router.route(message)

      expect(result.serialized[:protocolVersion]).to eq("2025-06-18")
    end
  end

  describe "router mapping" do
    context "logging/setLevel" do
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
              text: "I'm finna eat all my wife's leftovers.",
              title: "Top Secret Plans",
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

  describe "pagination integration tests" do
    let(:registry) do
      ModelContextProtocol::Server::Registry.new do
        resources do
          25.times do |i|
            resource_class = Class.new(ModelContextProtocol::Server::Resource) do
              define_method(:call) do |logger, context|
                ModelContextProtocol::Server::ReadResourceResponse[
                  contents: [
                    {
                      uri: "file:///resource_#{i}.txt",
                      mimeType: "text/plain",
                      text: "Content #{i}"
                    }
                  ]
                ]
              end
            end
            resource_class.define_singleton_method(:definition) do
              {
                name: "resource_#{i}",
                description: "Test resource #{i}",
                uri: "file:///resource_#{i}.txt",
                mimeType: "text/plain"
              }
            end
            register resource_class
          end
        end

        tools do
          15.times do |i|
            tool_class = Class.new(ModelContextProtocol::Server::Tool) do
              define_method(:call) do |args, logger, context|
                ModelContextProtocol::Server::CallToolResponse[
                  content: [
                    {
                      type: "text",
                      text: "Tool #{i} executed with args: #{args}"
                    }
                  ]
                ]
              end
            end
            tool_class.define_singleton_method(:definition) do
              {
                name: "tool_#{i}",
                description: "Test tool #{i}",
                inputSchema: {
                  type: "object",
                  properties: {
                    input: {type: "string"}
                  }
                }
              }
            end
            register tool_class
          end
        end

        prompts do
          30.times do |i|
            prompt_class = Class.new(ModelContextProtocol::Server::Prompt) do
              define_method(:call) do |args, logger, context|
                ModelContextProtocol::Server::GetPromptResponse[
                  description: "Test prompt #{i}",
                  messages: [
                    {
                      role: "user",
                      content: {
                        type: "text",
                        text: "Test prompt #{i} with args: #{args}"
                      }
                    }
                  ]
                ]
              end
            end
            prompt_class.define_singleton_method(:definition) do
              {
                name: "prompt_#{i}",
                description: "Test prompt #{i}",
                arguments: [{name: "input", description: "Input parameter"}]
              }
            end
            register prompt_class
          end
        end
      end
    end

    let(:server) do
      described_class.new do |config|
        config.name = "Pagination Test Server"
        config.version = "1.0.0"
        config.registry = registry
        config.pagination = {
          enabled: true,
          default_page_size: 10,
          max_page_size: 50
        }
      end
    end

    describe "resources/list with pagination" do
      it "returns first page when pageSize is specified" do
        message = {
          "method" => "resources/list",
          "params" => {"pageSize" => 10}
        }

        response = server.router.route(message)
        result = response.serialized

        aggregate_failures do
          expect(result[:resources].length).to eq(10)
          expect(result[:nextCursor]).not_to be_nil
          expect(result[:resources].first[:name]).to eq("resource_0")
          expect(result[:resources].last[:name]).to eq("resource_9")
        end
      end

      it "returns subsequent page using cursor" do
        first_message = {
          "method" => "resources/list",
          "params" => {"pageSize" => 10}
        }
        first_response = server.router.route(first_message).serialized

        second_message = {
          "method" => "resources/list",
          "params" => {
            "cursor" => first_response[:nextCursor],
            "pageSize" => 10
          }
        }
        second_response = server.router.route(second_message).serialized

        aggregate_failures do
          expect(second_response[:resources].length).to eq(10)
          expect(second_response[:resources].first[:name]).to eq("resource_10")
          expect(second_response[:resources].last[:name]).to eq("resource_19")
          expect(second_response[:nextCursor]).not_to be_nil
        end
      end

      it "returns last page with no nextCursor" do
        first_response = server.router.route({
          "method" => "resources/list",
          "params" => {"pageSize" => 10}
        }).serialized

        second_response = server.router.route({
          "method" => "resources/list",
          "params" => {
            "cursor" => first_response[:nextCursor],
            "pageSize" => 10
          }
        }).serialized

        third_response = server.router.route({
          "method" => "resources/list",
          "params" => {
            "cursor" => second_response[:nextCursor],
            "pageSize" => 10
          }
        }).serialized

        aggregate_failures do
          expect(third_response[:resources].length).to eq(5)
          expect(third_response[:nextCursor]).to be_nil
          expect(third_response[:resources].first[:name]).to eq("resource_20")
          expect(third_response[:resources].last[:name]).to eq("resource_24")
        end
      end

      it "returns all resources when no pagination params provided" do
        message = {"method" => "resources/list", "params" => {}}
        response = server.router.route(message).serialized

        aggregate_failures do
          expect(response[:resources].length).to eq(25)
          expect(response).not_to have_key(:nextCursor)
        end
      end

      it "respects max page size" do
        message = {
          "method" => "resources/list",
          "params" => {"pageSize" => 100}
        }

        response = server.router.route(message).serialized

        expect(response[:resources].length).to eq(25)
      end

      it "raises error for invalid cursor" do
        message = {
          "method" => "resources/list",
          "params" => {"cursor" => "invalid_cursor"}
        }

        expect {
          server.router.route(message)
        }.to raise_error(ModelContextProtocol::Server::ParameterValidationError, /Invalid cursor format/)
      end
    end

    describe "tools/list with pagination" do
      it "paginates tools correctly" do
        message = {
          "method" => "tools/list",
          "params" => {"pageSize" => 5}
        }

        response = server.router.route(message).serialized

        aggregate_failures do
          expect(response[:tools].length).to eq(5)
          expect(response[:nextCursor]).not_to be_nil
          expect(response[:tools].first[:name]).to eq("tool_0")
          expect(response[:tools].last[:name]).to eq("tool_4")
        end
      end
    end

    describe "prompts/list with pagination" do
      it "paginates prompts correctly" do
        message = {
          "method" => "prompts/list",
          "params" => {"pageSize" => 8}
        }

        response = server.router.route(message).serialized

        expect(response[:prompts].length).to eq(8)
        expect(response[:nextCursor]).not_to be_nil
        expect(response[:prompts].first[:name]).to eq("prompt_0")
        expect(response[:prompts].last[:name]).to eq("prompt_7")
      end
    end

    describe "capabilities" do
      it "does not include pagination capability (per MCP spec)" do
        message = {"method" => "initialize", "params" => {}}
        response = server.router.route(message).serialized

        expect(response[:capabilities]).not_to have_key(:pagination)
      end

      it "includes standard capabilities" do
        message = {"method" => "initialize", "params" => {}}
        response = server.router.route(message).serialized

        aggregate_failures do
          expect(response[:capabilities]).to have_key(:completions)
          expect(response[:capabilities]).to have_key(:logging)
        end
      end
    end

    describe "initialization response" do
      let(:registry) do
        ModelContextProtocol::Server::Registry.new do
          prompts do
            register TestPrompt
          end
        end
      end

      it "includes only required fields when title and instructions are not configured" do
        server = described_class.new do |config|
          config.name = "Test Server"
          config.version = "1.0.0"
          config.registry = registry
        end

        message = {"method" => "initialize", "params" => {}}
        response = server.router.route(message).serialized

        aggregate_failures do
          expect(response[:serverInfo][:name]).to eq("Test Server")
          expect(response[:serverInfo][:version]).to eq("1.0.0")
          expect(response[:serverInfo]).not_to have_key(:title)
          expect(response).not_to have_key(:instructions)
          expect(response[:protocolVersion]).to eq("2025-06-18")
          expect(response[:capabilities]).to be_a(Hash)
        end
      end

      it "includes title in serverInfo when configured" do
        server = described_class.new do |config|
          config.name = "Test Server"
          config.version = "1.0.0"
          config.title = "My Awesome Test Server"
          config.registry = registry
        end

        message = {"method" => "initialize", "params" => {}}
        response = server.router.route(message).serialized

        aggregate_failures do
          expect(response[:serverInfo][:name]).to eq("Test Server")
          expect(response[:serverInfo][:version]).to eq("1.0.0")
          expect(response[:serverInfo][:title]).to eq("My Awesome Test Server")
          expect(response).not_to have_key(:instructions)
        end
      end

      it "includes instructions when configured" do
        server = described_class.new do |config|
          config.name = "Test Server"
          config.version = "1.0.0"
          config.instructions = "This server provides test prompts and resources for development."
          config.registry = registry
        end

        message = {"method" => "initialize", "params" => {}}
        response = server.router.route(message).serialized

        aggregate_failures do
          expect(response[:serverInfo][:name]).to eq("Test Server")
          expect(response[:serverInfo][:version]).to eq("1.0.0")
          expect(response[:serverInfo]).not_to have_key(:title)
          expect(response[:instructions]).to eq("This server provides test prompts and resources for development.")
        end
      end

      it "includes both title and instructions when both are configured" do
        server = described_class.new do |config|
          config.name = "Test Server"
          config.version = "1.0.0"
          config.title = "Development Test Server"
          config.instructions = "Use this server for testing MCP functionality. Available tools include prompt completion and resource access."
          config.registry = registry
        end

        message = {"method" => "initialize", "params" => {}}
        response = server.router.route(message).serialized

        aggregate_failures do
          expect(response[:serverInfo][:name]).to eq("Test Server")
          expect(response[:serverInfo][:version]).to eq("1.0.0")
          expect(response[:serverInfo][:title]).to eq("Development Test Server")
          expect(response[:instructions]).to eq("Use this server for testing MCP functionality. Available tools include prompt completion and resource access.")
          expect(response[:protocolVersion]).to eq("2025-06-18")
          expect(response[:capabilities]).to be_a(Hash)
        end
      end
    end

    describe "cursor TTL functionality" do
      let(:short_ttl_server) do
        described_class.new do |config|
          config.name = "Short TTL Server"
          config.version = "1.0.0"
          config.registry = registry
          config.pagination = {
            enabled: true,
            default_page_size: 10,
            cursor_ttl: 1
          }
        end
      end

      it "handles expired cursors gracefully" do
        first_response = short_ttl_server.router.route({
          "method" => "resources/list",
          "params" => {"pageSize" => 10}
        }).serialized

        cursor = first_response[:nextCursor]

        sleep(2)

        message = {
          "method" => "resources/list",
          "params" => {"cursor" => cursor}
        }

        expect {
          short_ttl_server.router.route(message)
        }.to raise_error(ModelContextProtocol::Server::ParameterValidationError, /expired/)
      end
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
end
