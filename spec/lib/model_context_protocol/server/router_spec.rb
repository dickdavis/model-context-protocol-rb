require "spec_helper"

RSpec.describe ModelContextProtocol::Server::Router do
  subject(:router) { described_class.new }

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
    let(:configuration) { ModelContextProtocol::Server::Configuration.new }

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
  end

  describe "cancellation handling" do
    let(:request_store) { double("request_store") }
    let(:request_id) { "test-request-123" }
    let(:message) { {"method" => "cancellable_test", "id" => request_id} }

    before do
      router.map("cancellable_test") do |_|
        tool = TestToolWithCancellableSleep.new({}, double("logger", info: nil))
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
            request_id: context[:request_id],
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
          expect(result[:request_id]).to eq(request_id)
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
    end
  end
end
