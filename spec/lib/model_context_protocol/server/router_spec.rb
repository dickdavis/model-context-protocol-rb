require "spec_helper"

RSpec.describe ModelContextProtocol::Server::Router do
  let(:configuration) do
    ModelContextProtocol::Server::Configuration.new.tap do |config|
      config.name = "TestServer"
      config.version = "1.0.0"
      config.registry {}
    end
  end

  subject(:router) { described_class.new(configuration: configuration) }

  describe "#map" do
    it "registers a handler for a method" do
      router.map("test_method") { |_| "handler result" }
      result = router.route({"method" => "test_method"})
      expect(result).to eq("handler result")
    end
  end

  describe "#route" do
    let(:message) { {"method" => "test_method", "params" => {"key" => "value"}} }

    before do
      router.map("test_method") { |msg| msg["params"]["key"] }
    end

    it "routes the message to the correct handler" do
      result = router.route(message)
      expect(result).to eq("value")
    end

    it "passes the entire message to the handler" do
      full_message = nil
      router.map("echo_method") { |msg| full_message = msg }
      router.route({"method" => "echo_method", "id" => 123})
      expect(full_message).to eq({"method" => "echo_method", "id" => 123})
    end

    context "when the method is not registered" do
      let(:unknown_message) { {"method" => "unknown_method"} }

      it "raises MethodNotFoundError" do
        expect { router.route(unknown_message) }
          .to raise_error(ModelContextProtocol::Server::Router::MethodNotFoundError)
      end

      it "includes the method name in the error message" do
        expect { router.route(unknown_message) }
          .to raise_error(/Method not found: unknown_method/)
      end
    end
  end

  describe "error handling" do
    let(:message) { {"method" => "error_method"} }

    before do
      router.map("error_method") { |_| raise "Handler error" }
    end

    it "allows errors to propagate from handlers" do
      expect { router.route(message) }.to raise_error(RuntimeError, "Handler error")
    end
  end

  describe "multiple handlers" do
    before do
      router.map("method1") { |_| "result1" }
      router.map("method2") { |_| "result2" }
    end

    it "routes to the first handler" do
      expect(router.route({"method" => "method1"})).to eq("result1")
    end

    it "routes to the second handler" do
      expect(router.route({"method" => "method2"})).to eq("result2")
    end
  end

  describe "overwriting handlers" do
    it "uses the last registered handler for a method" do
      router.map("test_method") { |_| "first handler" }
      router.map("test_method") { |_| "second handler" }

      expect(router.route({"method" => "test_method"})).to eq("second handler")
    end
  end

  describe "handling complex logic" do
    it "can perform transformations on the input" do
      router.map("transform") do |message|
        items = message["params"]["items"]
        items.map { |item| item * 2 }
      end

      result = router.route({
        "method" => "transform",
        "params" => {"items" => [1, 2, 3]}
      })

      expect(result).to eq([2, 4, 6])
    end

    it "can maintain state between calls" do
      counter = 0
      router.map("counter") { |_| counter += 1 }

      aggregate_failures do
        expect(router.route({"method" => "counter"})).to eq(1)
        expect(router.route({"method" => "counter"})).to eq(2)
        expect(router.route({"method" => "counter"})).to eq(3)
      end
    end
  end

  describe "environment variable management" do
    subject(:router) { described_class.new(configuration: configuration) }
    let(:message) { {"method" => "env_test"} }
    let(:configuration) { ModelContextProtocol::Server::StdioConfiguration.new }

    before do
      ENV["EXISTING_VAR"] = "original_value"
      ENV["ANOTHER_VAR"] = "another_value"
    end

    after do
      ENV.delete("EXISTING_VAR")
      ENV.delete("ANOTHER_VAR")
      ENV.delete("TEST_VAR")
      ENV.delete("OVERRIDE_VAR")
    end

    it "sets environment variables during handler execution" do
      router.map("env_test") do
        ENV["TEST_VAR"]
      end

      configuration.set_environment_variable("TEST_VAR", "test_value")
      result = router.route(message)

      expect(result).to eq("test_value")
    end

    it "overrides existing environment variables" do
      router.map("env_test") do
        ENV["EXISTING_VAR"]
      end

      configuration.set_environment_variable("EXISTING_VAR", "new_value")
      result = router.route(message)

      expect(result).to eq("new_value")
    end

    it "restores original environment variables after handler execution" do
      router.map("env_test") do
        ENV["EXISTING_VAR"] = "changed_value"
        "done"
      end

      router.route(message)

      expect(ENV["EXISTING_VAR"]).to eq("original_value")
    end

    it "restores environment variables even if handler raises an error" do
      router.map("env_test") do
        ENV["EXISTING_VAR"] = "changed_value"
        raise "Handler error"
      end

      aggregate_failures do
        expect { router.route(message) }.to raise_error(RuntimeError, "Handler error")
        expect(ENV["EXISTING_VAR"]).to eq("original_value")
      end
    end

    it "handles multiple environment variables" do
      router.map("env_test") do
        [ENV["TEST_VAR"], ENV["OVERRIDE_VAR"]]
      end

      configuration.set_environment_variable("TEST_VAR", "test_value")
      configuration.set_environment_variable("OVERRIDE_VAR", "override_value")
      result = router.route(message)

      expect(result).to eq(["test_value", "override_value"])
    end

    context "when transport is streamable_http" do
      let(:configuration) { ModelContextProtocol::Server::StreamableHttpConfiguration.new }

      it "does NOT manipulate ENV variables (thread-safety)" do
        router.map("env_test") do
          ENV["EXISTING_VAR"]
        end

        result = router.route(message)

        # ENV should NOT be modified for streamable_http
        expect(result).to eq("original_value")
      end

      it "does not restore ENV after handler execution" do
        original_existing = ENV["EXISTING_VAR"]

        router.map("env_test") do
          ENV["EXISTING_VAR"] = "changed_by_handler"
          "done"
        end

        router.route(message)

        # Since ENV manipulation is skipped, the handler's change persists
        expect(ENV["EXISTING_VAR"]).to eq("changed_by_handler")

        # Restore for other tests
        ENV["EXISTING_VAR"] = original_existing
      end

      it "still sets thread-local context correctly" do
        router.map("env_test") do
          Thread.current[:mcp_context][:session_context]
        end

        result = router.route(message, session_context: {user_id: "test-123"})

        expect(result).to eq({user_id: "test-123"})
      end
    end
  end

  describe "cancellation handling" do
    let(:request_store) { double("request_store") }
    let(:request_id) { "test-request-123" }
    let(:message) { {"method" => "cancellable_test", "id" => request_id} }

    before do
      router.map("cancellable_test") do |_|
        client_logger = double("logger", info: nil)
        server_logger = ModelContextProtocol::Server::ServerLogger.new
        tool = TestToolWithCancellableShortSleep.new({}, client_logger, server_logger)
        response = tool.call
        response.content.first.text
      end
    end

    context "when request is not cancelled" do
      it "executes normally and returns result" do
        allow(request_store).to receive(:register_request)
        allow(request_store).to receive(:unregister_request)
        allow(request_store).to receive(:cancelled?).with(request_id).and_return(false)

        result = router.route(message, request_store: request_store)

        aggregate_failures do
          expect(result).to eq("Sleep completed successfully")
          expect(request_store).to have_received(:register_request).with(request_id, nil)
          expect(request_store).to have_received(:unregister_request).with(request_id)
        end
      end
    end

    context "when request is cancelled before execution" do
      it "returns nil and cleans up properly" do
        allow(request_store).to receive(:register_request)
        allow(request_store).to receive(:unregister_request)
        allow(request_store).to receive(:cancelled?).with(request_id).and_return(true)

        result = router.route(message, request_store: request_store)

        aggregate_failures do
          expect(result).to be_nil
          expect(request_store).to have_received(:register_request).with(request_id, nil)
          expect(request_store).to have_received(:unregister_request).with(request_id)
        end
      end
    end

    context "when request is cancelled during execution" do
      it "returns nil and cleans up properly" do
        allow(request_store).to receive(:register_request)
        allow(request_store).to receive(:unregister_request)

        call_count = 0
        allow(request_store).to receive(:cancelled?).with(request_id) do
          call_count += 1
          call_count > 1
        end

        start_time = Time.now
        result = router.route(message, request_store: request_store)
        elapsed = Time.now - start_time

        aggregate_failures do
          expect(result).to be_nil
          expect(elapsed).to be < 0.5
          expect(request_store).to have_received(:register_request).with(request_id, nil)
          expect(request_store).to have_received(:unregister_request).with(request_id)
        end
      end
    end

    context "when no request store is provided" do
      it "executes normally without cancellation support" do
        result = router.route(message)
        expect(result).to eq("Sleep completed successfully")
      end
    end

    context "when message has no id" do
      let(:message_without_id) { {"method" => "cancellable_test"} }

      it "executes normally without request tracking" do
        allow(request_store).to receive(:register_request)
        allow(request_store).to receive(:unregister_request)

        result = router.route(message_without_id, request_store: request_store)

        aggregate_failures do
          expect(result).to eq("Sleep completed successfully")
          expect(request_store).not_to have_received(:register_request)
          expect(request_store).not_to have_received(:unregister_request)
        end
      end
    end

    context "thread-local context management" do
      it "sets and cleans up thread-local context" do
        allow(request_store).to receive(:register_request)
        allow(request_store).to receive(:unregister_request)
        allow(request_store).to receive(:cancelled?).with(request_id).and_return(false)

        router.map("context_test") do |_|
          context = Thread.current[:mcp_context]
          {
            jsonrpc_request_id: context[:jsonrpc_request_id],
            has_request_store: !context[:request_store].nil?,
            session_id: context[:session_id]
          }
        end

        result = router.route(
          {"method" => "context_test", "id" => request_id},
          request_store: request_store,
          session_id: "test-session"
        )

        aggregate_failures do
          expect(result[:jsonrpc_request_id]).to eq(request_id)
          expect(result[:has_request_store]).to be true
          expect(result[:session_id]).to eq("test-session")
          expect(Thread.current[:mcp_context]).to be_nil
        end
      end

      it "cleans up context even when cancellation occurs" do
        allow(request_store).to receive(:register_request)
        allow(request_store).to receive(:unregister_request)
        allow(request_store).to receive(:cancelled?).with(request_id).and_return(true)

        router.route(message, request_store: request_store)

        expect(Thread.current[:mcp_context]).to be_nil
      end

      it "includes session_context in thread-local context" do
        router.map("session_context_test") do |_|
          context = Thread.current[:mcp_context]
          {
            session_context: context[:session_context],
            user_id: context[:session_context][:user_id]
          }
        end

        result = router.route(
          {"method" => "session_context_test", "id" => "test-123"},
          session_context: {user_id: "user-456", tenant: "acme"}
        )

        aggregate_failures do
          expect(result[:session_context]).to eq({user_id: "user-456", tenant: "acme"})
          expect(result[:user_id]).to eq("user-456")
          expect(Thread.current[:mcp_context]).to be_nil
        end
      end

      it "defaults session_context to empty hash when not provided" do
        router.map("no_session_context_test") do |_|
          Thread.current[:mcp_context][:session_context]
        end

        result = router.route({"method" => "no_session_context_test", "id" => "test-789"})

        expect(result).to eq({})
      end
    end

    context "thread safety" do
      it "isolates context between concurrent requests" do
        router.map("thread_test") do |_|
          context = Thread.current[:mcp_context]
          # Simulate some work
          sleep(0.01)
          {
            session_context: context[:session_context],
            thread_id: Thread.current.object_id
          }
        end

        threads = []
        results = Concurrent::Array.new

        5.times do |i|
          threads << Thread.new do
            result = router.route(
              {"method" => "thread_test", "id" => "thread-#{i}"},
              session_context: {request_number: i}
            )
            results << result
          end
        end

        threads.each(&:join)

        # Each result should have its own context
        aggregate_failures do
          expect(results.size).to eq(5)
          results.each_with_index do |result, i|
            # Find the result matching this request number
            matching = results.find { |r| r[:session_context][:request_number] == i }
            expect(matching).not_to be_nil
          end
        end
      end

      it "cleans up thread-local context even with concurrent requests" do
        router.map("cleanup_test") do |_|
          sleep(0.01)
          "done"
        end

        threads = 10.times.map do |i|
          Thread.new do
            router.route(
              {"method" => "cleanup_test", "id" => "cleanup-#{i}"},
              session_context: {user: "user-#{i}"}
            )
            Thread.current[:mcp_context]
          end
        end

        results = threads.map(&:value)

        # All thread-local contexts should be cleaned up
        expect(results).to all(be_nil)
      end
    end
  end

  describe "progress token handling" do
    let(:transport) { double("transport") }
    let(:progress_token) { "test-progress-token-123" }
    let(:request_id) { "test-request-456" }

    before do
      router.map("progress_test") do |_|
        context = Thread.current[:mcp_context]
        {
          progress_token: context&.dig(:progress_token),
          transport: context&.dig(:transport),
          jsonrpc_request_id: context&.dig(:jsonrpc_request_id)
        }
      end
    end

    context "when progress token is provided in params._meta" do
      let(:message) do
        {
          "method" => "progress_test",
          "id" => request_id,
          "params" => {
            "data" => "test",
            "_meta" => {
              "progressToken" => progress_token
            }
          }
        }
      end

      it "extracts progress token and makes it available in thread context" do
        result = router.route(message, transport: transport)

        aggregate_failures do
          expect(result[:progress_token]).to eq(progress_token)
          expect(result[:transport]).to eq(transport)
          expect(result[:jsonrpc_request_id]).to eq(request_id)
        end
      end
    end

    context "when progress token is not provided" do
      let(:message) do
        {
          "method" => "progress_test",
          "id" => request_id,
          "params" => {
            "data" => "test"
          }
        }
      end

      it "sets progress token to nil in thread context" do
        result = router.route(message, transport: transport)

        aggregate_failures do
          expect(result[:progress_token]).to be_nil
          expect(result[:transport]).to eq(transport)
          expect(result[:jsonrpc_request_id]).to eq(request_id)
        end
      end
    end

    context "when params is nil" do
      let(:message) do
        {
          "method" => "progress_test",
          "id" => request_id
        }
      end

      it "handles missing params gracefully" do
        result = router.route(message, transport: transport)

        aggregate_failures do
          expect(result[:progress_token]).to be_nil
          expect(result[:transport]).to eq(transport)
          expect(result[:jsonrpc_request_id]).to eq(request_id)
        end
      end
    end

    context "when transport is not provided" do
      let(:message) do
        {
          "method" => "progress_test",
          "id" => request_id,
          "params" => {
            "_meta" => {
              "progressToken" => progress_token
            }
          }
        }
      end

      it "sets transport to nil in thread context" do
        result = router.route(message)

        aggregate_failures do
          expect(result[:progress_token]).to eq(progress_token)
          expect(result[:transport]).to be_nil
          expect(result[:jsonrpc_request_id]).to eq(request_id)
        end
      end
    end
  end

  describe "protocol version negotiation" do
    let(:router) do
      config = ModelContextProtocol::Server::Configuration.new.tap do |c|
        c.name = "Test Server"
        c.version = "1.0.0"
        c.registry {}
      end
      described_class.new(configuration: config)
    end

    it "returns client's protocol version when supported" do
      message = {
        "method" => "initialize",
        "id" => "init-1",
        "params" => {
          "protocolVersion" => "2025-06-18"
        }
      }

      result = router.route(message)

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

      result = router.route(message)

      expect(result.serialized[:protocolVersion]).to eq("2025-06-18")
    end

    it "returns server's latest version when no protocol version provided" do
      message = {
        "method" => "initialize",
        "id" => "init-1",
        "params" => {}
      }

      result = router.route(message)

      expect(result.serialized[:protocolVersion]).to eq("2025-06-18")
    end
  end

  describe "handler mapping" do
    context "logging/setLevel" do
      it "sets the log level when valid" do
        config = ModelContextProtocol::Server::Configuration.new.tap do |c|
          c.name = "Test Server"
          c.version = "1.0.0"
          c.registry {}
        end
        router = described_class.new(configuration: config)

        message = {
          "method" => "logging/setLevel",
          "params" => {"level" => "debug"}
        }

        expect(config.client_logger).to receive(:set_mcp_level).with("debug")
        response = router.route(message)
        expect(response.serialized).to eq({})
      end

      it "raises error for invalid log level" do
        config = ModelContextProtocol::Server::Configuration.new.tap do |c|
          c.name = "Test Server"
          c.version = "1.0.0"
          c.registry {}
        end
        router = described_class.new(configuration: config)

        message = {
          "method" => "logging/setLevel",
          "params" => {"level" => "invalid"}
        }

        expect {
          router.route(message)
        }.to raise_error(ModelContextProtocol::Server::ParameterValidationError, /Invalid log level: invalid/)
      end
    end

    context "completion/complete" do
      it "raises an error when an invalid ref/type is provided" do
        config = ModelContextProtocol::Server::Configuration.new.tap do |c|
          c.name = "Test Server"
          c.version = "1.0.0"
          c.registry do
            prompts do
              register TestPrompt
            end

            resource_templates do
              register TestResourceTemplate
            end
          end
        end
        router = described_class.new(configuration: config)

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
          router.route(message)
        }.to raise_error(ModelContextProtocol::Server::ParameterValidationError, "ref/type invalid")
      end

      context "for prompts" do
        it "returns a completion for the given prompt" do
          config = ModelContextProtocol::Server::Configuration.new.tap do |c|
            c.name = "Test Server"
            c.version = "1.0.0"
            c.registry do
              prompts { register TestPrompt }
            end
          end
          router = described_class.new(configuration: config)

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

          response = router.route(message)

          expect(response.serialized).to eq(
            completion: {
              values: ["whiny"],
              total: 1,
              hasMore: false
            }
          )
        end

        it "returns a null completion when no matching prompt is found" do
          config = ModelContextProtocol::Server::Configuration.new.tap do |c|
            c.name = "Test Server"
            c.version = "1.0.0"
            c.registry do
              prompts { register TestPrompt }
            end
          end
          router = described_class.new(configuration: config)

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

          response = router.route(message)

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
          config = ModelContextProtocol::Server::Configuration.new.tap do |c|
            c.name = "Test Server"
            c.version = "1.0.0"
            c.registry do
              resource_templates { register TestResourceTemplate }
            end
          end
          router = described_class.new(configuration: config)

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

          response = router.route(message)

          expect(response.serialized).to eq(
            completion: {
              values: ["top-secret-plans.txt"],
              total: 1,
              hasMore: false
            }
          )
        end

        it "returns a null completion when no matching resource template is found" do
          config = ModelContextProtocol::Server::Configuration.new.tap do |c|
            c.name = "Test Server"
            c.version = "1.0.0"
            c.registry do
              resource_templates { register TestResourceTemplate }
            end
          end
          router = described_class.new(configuration: config)

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

          response = router.route(message)

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
        config = ModelContextProtocol::Server::Configuration.new.tap do |c|
          c.name = "Test Server"
          c.version = "1.0.0"
          c.registry do
            resources { register TestResource }
          end
        end
        router = described_class.new(configuration: config)

        test_uri = "resource:///invalid"
        message = {"method" => "resources/read", "params" => {"uri" => test_uri}}

        expect {
          router.route(message)
        }.to raise_error(ModelContextProtocol::Server::ParameterValidationError, "resource not found for #{test_uri}")
      end

      it "returns the serialized resource data when the resource is found" do
        config = ModelContextProtocol::Server::Configuration.new.tap do |c|
          c.name = "Test Server"
          c.version = "1.0.0"
          c.registry do
            resources { register TestResource }
          end
        end
        router = described_class.new(configuration: config)

        test_uri = "file:///top-secret-plans.txt"
        message = {"method" => "resources/read", "params" => {"uri" => test_uri}}

        response = router.route(message)

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
        config = ModelContextProtocol::Server::Configuration.new.tap do |c|
          c.name = "Test Server"
          c.version = "1.0.0"
          c.registry do
            resource_templates { register TestResourceTemplate }
          end
        end
        router = described_class.new(configuration: config)

        message = {"method" => "resources/templates/list"}
        response = router.route(message)
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
              define_method(:call) do |args, client_logger, context|
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
              define_method(:call) do |args, client_logger, context|
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

    let(:router) do
      config = ModelContextProtocol::Server::Configuration.new.tap do |c|
        c.name = "Pagination Test Server"
        c.version = "1.0.0"
        c.instance_variable_set(:@registry, registry)
        c.pagination = {
          enabled: true,
          default_page_size: 10,
          max_page_size: 50
        }
      end
      described_class.new(configuration: config)
    end

    describe "resources/list with pagination" do
      it "returns first page when pageSize is specified" do
        message = {
          "method" => "resources/list",
          "params" => {"pageSize" => 10}
        }

        response = router.route(message)
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
        first_response = router.route(first_message).serialized

        second_message = {
          "method" => "resources/list",
          "params" => {
            "cursor" => first_response[:nextCursor],
            "pageSize" => 10
          }
        }
        second_response = router.route(second_message).serialized

        aggregate_failures do
          expect(second_response[:resources].length).to eq(10)
          expect(second_response[:resources].first[:name]).to eq("resource_10")
          expect(second_response[:resources].last[:name]).to eq("resource_19")
          expect(second_response[:nextCursor]).not_to be_nil
        end
      end

      it "returns last page with no nextCursor" do
        first_response = router.route({
          "method" => "resources/list",
          "params" => {"pageSize" => 10}
        }).serialized

        second_response = router.route({
          "method" => "resources/list",
          "params" => {
            "cursor" => first_response[:nextCursor],
            "pageSize" => 10
          }
        }).serialized

        third_response = router.route({
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
        response = router.route(message).serialized

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

        response = router.route(message).serialized

        expect(response[:resources].length).to eq(25)
      end

      it "raises error for invalid cursor" do
        message = {
          "method" => "resources/list",
          "params" => {"cursor" => "invalid_cursor"}
        }

        expect {
          router.route(message)
        }.to raise_error(ModelContextProtocol::Server::ParameterValidationError, /Invalid cursor format/)
      end
    end

    describe "tools/list with pagination" do
      it "paginates tools correctly" do
        message = {
          "method" => "tools/list",
          "params" => {"pageSize" => 5}
        }

        response = router.route(message).serialized

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

        response = router.route(message).serialized

        expect(response[:prompts].length).to eq(8)
        expect(response[:nextCursor]).not_to be_nil
        expect(response[:prompts].first[:name]).to eq("prompt_0")
        expect(response[:prompts].last[:name]).to eq("prompt_7")
      end
    end

    describe "capabilities" do
      it "does not include pagination capability (per MCP spec)" do
        message = {"method" => "initialize", "params" => {}}
        response = router.route(message).serialized

        expect(response[:capabilities]).not_to have_key(:pagination)
      end

      it "includes standard capabilities" do
        message = {"method" => "initialize", "params" => {}}
        response = router.route(message).serialized

        aggregate_failures do
          expect(response[:capabilities]).to have_key(:completions)
          expect(response[:capabilities]).to have_key(:logging)
        end
      end
    end

    describe "initialization response" do
      it "includes only required fields when title and instructions are not configured" do
        config = ModelContextProtocol::Server::Configuration.new.tap do |c|
          c.name = "Test Server"
          c.version = "1.0.0"
          c.registry do
            prompts { register TestPrompt }
          end
        end
        router = described_class.new(configuration: config)

        message = {"method" => "initialize", "params" => {}}
        response = router.route(message).serialized

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
        config = ModelContextProtocol::Server::Configuration.new.tap do |c|
          c.name = "Test Server"
          c.version = "1.0.0"
          c.title = "My Awesome Test Server"
          c.registry do
            prompts { register TestPrompt }
          end
        end
        router = described_class.new(configuration: config)

        message = {"method" => "initialize", "params" => {}}
        response = router.route(message).serialized

        aggregate_failures do
          expect(response[:serverInfo][:name]).to eq("Test Server")
          expect(response[:serverInfo][:version]).to eq("1.0.0")
          expect(response[:serverInfo][:title]).to eq("My Awesome Test Server")
          expect(response).not_to have_key(:instructions)
        end
      end

      it "includes instructions when configured" do
        config = ModelContextProtocol::Server::Configuration.new.tap do |c|
          c.name = "Test Server"
          c.version = "1.0.0"
          c.instructions = "This server provides test prompts and resources for development."
          c.registry do
            prompts { register TestPrompt }
          end
        end
        router = described_class.new(configuration: config)

        message = {"method" => "initialize", "params" => {}}
        response = router.route(message).serialized

        aggregate_failures do
          expect(response[:serverInfo][:name]).to eq("Test Server")
          expect(response[:serverInfo][:version]).to eq("1.0.0")
          expect(response[:serverInfo]).not_to have_key(:title)
          expect(response[:instructions]).to eq("This server provides test prompts and resources for development.")
        end
      end

      it "includes both title and instructions when both are configured" do
        config = ModelContextProtocol::Server::Configuration.new.tap do |c|
          c.name = "Test Server"
          c.version = "1.0.0"
          c.title = "Development Test Server"
          c.instructions = "Use this server for testing MCP functionality. Available tools include prompt completion and resource access."
          c.registry do
            prompts { register TestPrompt }
          end
        end
        router = described_class.new(configuration: config)

        message = {"method" => "initialize", "params" => {}}
        response = router.route(message).serialized

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
      let(:short_ttl_router) do
        config = ModelContextProtocol::Server::Configuration.new.tap do |c|
          c.name = "Short TTL Server"
          c.version = "1.0.0"
          c.instance_variable_set(:@registry, registry)
          c.pagination = {
            enabled: true,
            default_page_size: 10,
            cursor_ttl: 1
          }
        end
        described_class.new(configuration: config)
      end

      it "handles expired cursors gracefully" do
        first_response = short_ttl_router.route({
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
          short_ttl_router.route(message)
        }.to raise_error(ModelContextProtocol::Server::ParameterValidationError, /expired/)
      end
    end
  end

  describe "listChanged capability by transport type" do
    let(:registry_block) do
      proc do
        prompts { register TestPrompt }
        resources(subscribe: true) { register TestResource }
        tools { register TestToolWithTextResponse }
      end
    end

    context "with stdio transport (default)" do
      let(:router) do
        blk = registry_block
        config = ModelContextProtocol::Server::Configuration.new.tap do |c|
          c.name = "Test Server"
          c.version = "1.0.0"
          c.registry(&blk)
          # transport_type defaults to :stdio or nil
        end
        described_class.new(configuration: config)
      end

      it "does NOT advertise listChanged capability" do
        message = {"method" => "initialize", "params" => {}}
        response = router.route(message).serialized

        aggregate_failures do
          # listChanged should be suppressed for stdio
          expect(response[:capabilities][:prompts]).to eq({})
          expect(response[:capabilities][:resources]).to eq({subscribe: true})
          expect(response[:capabilities][:tools]).to eq({})
        end
      end
    end

    context "with streamable_http transport" do
      let(:router) do
        blk = registry_block
        config = ModelContextProtocol::Server::StreamableHttpConfiguration.new.tap do |c|
          c.name = "Test Server"
          c.version = "1.0.0"
          c.registry(&blk)
        end
        described_class.new(configuration: config)
      end

      it "automatically advertises listChanged capability" do
        message = {"method" => "initialize", "params" => {}}
        response = router.route(message).serialized

        aggregate_failures do
          expect(response[:capabilities][:prompts]).to eq({listChanged: true})
          expect(response[:capabilities][:resources]).to eq({subscribe: true, listChanged: true})
          expect(response[:capabilities][:tools]).to eq({listChanged: true})
        end
      end
    end
  end

  describe "stream_id handling" do
    let(:stream_id) { "test-stream-abc123" }
    let(:request_id) { "test-request-789" }

    before do
      router.map("stream_test") do |_|
        context = Thread.current[:mcp_context]
        {
          stream_id: context&.dig(:stream_id),
          session_id: context&.dig(:session_id),
          jsonrpc_request_id: context&.dig(:jsonrpc_request_id)
        }
      end
    end

    context "when stream_id is provided" do
      let(:message) { {"method" => "stream_test", "id" => request_id} }

      it "makes stream_id available in thread context" do
        result = router.route(message, stream_id: stream_id)

        aggregate_failures do
          expect(result[:stream_id]).to eq(stream_id)
          expect(result[:jsonrpc_request_id]).to eq(request_id)
        end
      end

      it "keeps stream_id separate from session_id" do
        result = router.route(message, session_id: "session-456", stream_id: stream_id)

        aggregate_failures do
          expect(result[:stream_id]).to eq(stream_id)
          expect(result[:session_id]).to eq("session-456")
        end
      end
    end

    context "when stream_id is not provided" do
      let(:message) { {"method" => "stream_test", "id" => request_id} }

      it "sets stream_id to nil in thread context" do
        result = router.route(message)

        expect(result[:stream_id]).to be_nil
      end
    end

    context "context cleanup" do
      let(:message) { {"method" => "stream_test", "id" => request_id} }

      it "cleans up stream_id from thread context after execution" do
        router.route(message, stream_id: stream_id)

        expect(Thread.current[:mcp_context]).to be_nil
      end

      it "cleans up stream_id even when handler raises an error" do
        router.map("error_stream_test") { |_| raise "Handler error" }

        expect {
          router.route({"method" => "error_stream_test", "id" => request_id}, stream_id: stream_id)
        }.to raise_error(RuntimeError, "Handler error")

        expect(Thread.current[:mcp_context]).to be_nil
      end
    end
  end
end
