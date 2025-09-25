require "spec_helper"

TestResponse = Data.define(:text) do
  def serialized
    {text:}
  end
end

RSpec.describe ModelContextProtocol::Server::StdioTransport do
  subject(:transport) { described_class.new(router: router, configuration: configuration) }

  let(:router) { ModelContextProtocol::Server::Router.new }
  let(:configuration) { ModelContextProtocol::Server::Configuration.new }
  let(:mcp_logger) { configuration.logger }

  before do
    @original_stdin = $stdin
    @original_stdout = $stdout
    $stdin = StringIO.new
    $stdout = StringIO.new

    router.map("test_method") do |_|
      TestResponse[text: "foobar"]
    end

    router.map("error") do |_|
      raise "Something went wrong"
    end

    router.map("validation_error") do |_|
      raise ModelContextProtocol::Server::ParameterValidationError, "Invalid parameters"
    end
  end

  after do
    $stdin = @original_stdin
    $stdout = @original_stdout
  end

  describe "#handle" do
    context "with a valid request" do
      let(:request) { {"jsonrpc" => "2.0", "id" => 1, "method" => "test_method"} }

      before do
        $stdin.puts(JSON.generate(request))
        $stdin.rewind
      end

      it "processes the request and sends a response" do
        begin
          transport.handle
        rescue EOFError
          # Expected to raise EOFError when stdin is exhausted
        end

        $stdout.rewind
        output = $stdout.read
        response_json = JSON.parse(output)
        aggregate_failures do
          expect(response_json["jsonrpc"]).to eq("2.0")
          expect(response_json["id"]).to eq(1)
          expect(response_json["result"]).to eq({"text" => "foobar"})
        end
      end
    end

    context "with a notification" do
      before do
        $stdin.puts(JSON.generate({"jsonrpc" => "2.0", "method" => "notifications/something"}))
        $stdin.puts(JSON.generate({"jsonrpc" => "2.0", "id" => 2, "method" => "test_method"}))
        $stdin.rewind
      end

      it "does not process notifications" do
        begin
          transport.handle
        rescue EOFError
          # Expected
        end

        $stdout.rewind
        output = $stdout.read
        response_lines = output.strip.split("\n")

        aggregate_failures do
          expect(response_lines.length).to eq(1)
          response_json = JSON.parse(response_lines[0])
          expect(response_json["id"]).to eq(2)
        end
      end
    end

    context "with a JSON parse error" do
      before do
        $stdin.puts("invalid json")
        $stdin.rewind
      end

      it "sends an error response" do
        allow(mcp_logger).to receive(:error)

        begin
          transport.handle
        rescue EOFError
          # Expected
        end

        $stdout.rewind
        output = $stdout.read
        lines = output.strip.split("\n")

        aggregate_failures do
          expect(lines.length).to eq(1)
          error_response = JSON.parse(lines[0])
          expect(error_response).to include("error")
          expect(error_response["error"]["code"]).to eq(-32700)
          expect(error_response["error"]["message"]).to include("unexpected token")
          expect(mcp_logger).to have_received(:error).with("Parser error", error: String)
        end
      end
    end

    context "with a parameter validation error" do
      let(:request) { {"jsonrpc" => "2.0", "id" => 2, "method" => "validation_error"} }

      before do
        $stdin.puts(JSON.generate(request))
        $stdin.rewind
      end

      it "sends a validation error response" do
        allow(mcp_logger).to receive(:error)

        begin
          transport.handle
        rescue EOFError
          # Expected
        end

        $stdout.rewind
        output = $stdout.read
        response_json = JSON.parse(output)

        aggregate_failures do
          expect(response_json).to include("error")
          expect(response_json["error"]["code"]).to eq(-32602)
          expect(response_json["error"]["message"]).to eq("Invalid parameters")
          expect(mcp_logger).to have_received(:error).with("Validation error", error: "Invalid parameters")
        end
      end
    end

    context "with an internal error" do
      let(:request) { {"jsonrpc" => "2.0", "id" => 3, "method" => "error"} }

      before do
        $stdin.puts(JSON.generate(request))
        $stdin.rewind
      end

      it "sends an internal error response" do
        allow(mcp_logger).to receive(:error)

        begin
          transport.handle
        rescue EOFError
          # Expected
        end

        $stdout.rewind
        output = $stdout.read
        response_json = JSON.parse(output)

        aggregate_failures do
          expect(response_json).to include("error")
          expect(response_json["error"]["code"]).to eq(-32603)
          expect(response_json["error"]["message"]).to eq("Something went wrong")
          expect(mcp_logger).to have_received(:error).with("Internal error",
            error: "Something went wrong",
            backtrace: kind_of(Array))
        end
      end
    end

    context "with multiple requests" do
      before do
        router.map("method1") do |message|
          TestResponse[text: "method1 response"]
        end

        router.map("method2") do |message|
          TestResponse[text: "method2 response"]
        end

        $stdin.puts(JSON.generate({"jsonrpc" => "2.0", "id" => 1, "method" => "method1"}))
        $stdin.puts(JSON.generate({"jsonrpc" => "2.0", "id" => 2, "method" => "method2"}))
        $stdin.rewind
      end

      it "processes all requests in sequence" do
        begin
          transport.handle
        rescue EOFError
          # Expected
        end

        $stdout.rewind
        output = $stdout.read
        responses = output.strip.split("\n").map { |line| JSON.parse(line) }

        aggregate_failures do
          expect(responses.length).to eq(2)
          expect(responses[0]["id"]).to eq(1)
          expect(responses[0]["result"]).to eq({"text" => "method1 response"})
          expect(responses[1]["id"]).to eq(2)
          expect(responses[1]["result"]).to eq({"text" => "method2 response"})
        end
      end
    end
  end

  describe "MCP logging integration" do
    it "connects the logger to the transport when handle starts" do
      expect(mcp_logger).to receive(:connect_transport).with(transport)

      begin
        transport.handle
      rescue EOFError
        # Expected when stdin is empty
      end
    end

    describe "#send_notification" do
      before do
        # Connect logger so notifications can be sent
        mcp_logger.connect_transport(transport)
      end

      it "sends MCP notifications to stdout" do
        transport.send_notification("notifications/message", {
          level: "info",
          logger: "test",
          data: {message: "test notification"}
        })

        $stdout.rewind
        output = $stdout.read
        notification = JSON.parse(output)

        aggregate_failures do
          expect(notification["jsonrpc"]).to eq("2.0")
          expect(notification["method"]).to eq("notifications/message")
          expect(notification["params"]["level"]).to eq("info")
          expect(notification["params"]["logger"]).to eq("test")
          expect(notification["params"]["data"]["message"]).to eq("test notification")
        end
      end

      it "handles broken pipe gracefully" do
        allow($stdout).to receive(:puts).and_raise(IOError, "broken pipe")
        allow($stdout).to receive(:flush)

        expect {
          transport.send_notification("notifications/message", {level: "error", data: {}})
        }.not_to raise_error
      end
    end
  end

  describe "Response class" do
    it "creates a properly formatted JSON-RPC response" do
      response = described_class::Response.new(id: 123, result: {data: "value"})

      expect(response.serialized).to eq(
        {
          jsonrpc: "2.0",
          id: 123,
          result: {data: "value"}
        }
      )
    end
  end

  describe "ErrorResponse class" do
    it "creates a properly formatted JSON-RPC error response" do
      error_response = described_class::ErrorResponse.new(
        id: 456,
        error: {code: -32603, message: "Test error"}
      )

      expect(error_response.serialized).to eq(
        {
          jsonrpc: "2.0",
          id: 456,
          error: {code: -32603, message: "Test error"}
        }
      )
    end
  end

  describe "cancellation handling" do
    let(:request_id) { "test-request-123" }
    let(:reason) { "User requested cancellation" }
    let(:cancellation_message) do
      {
        "jsonrpc" => "2.0",
        "method" => "notifications/cancelled",
        "params" => {
          "requestId" => request_id,
          "reason" => reason
        }
      }
    end

    describe "#handle_cancellation" do
      context "when request exists in store" do
        before do
          request_store = transport.instance_variable_get(:@request_store)
          request_store.register_request(request_id)
        end

        it "marks the request as cancelled" do
          transport.send(:handle_cancellation, cancellation_message)

          request_store = transport.instance_variable_get(:@request_store)
          expect(request_store.cancelled?(request_id)).to be true
        end
      end

      context "when request does not exist in store" do
        it "does not raise error for unknown request" do
          expect {
            transport.send(:handle_cancellation, cancellation_message)
          }.not_to raise_error
        end
      end

      context "with malformed cancellation message" do
        it "handles missing params gracefully" do
          malformed_message = {"method" => "notifications/cancelled"}

          expect {
            transport.send(:handle_cancellation, malformed_message)
          }.not_to raise_error
        end

        it "handles missing request ID gracefully" do
          malformed_message = {
            "method" => "notifications/cancelled",
            "params" => {"reason" => "test reason"}
          }

          expect {
            transport.send(:handle_cancellation, malformed_message)
          }.not_to raise_error
        end
      end

      context "when cancellation without reason" do
        let(:cancellation_without_reason) do
          {
            "method" => "notifications/cancelled",
            "params" => {"requestId" => request_id}
          }
        end

        before do
          request_store = transport.instance_variable_get(:@request_store)
          request_store.register_request(request_id)
        end

        it "marks request as cancelled with nil reason" do
          transport.send(:handle_cancellation, cancellation_without_reason)

          request_store = transport.instance_variable_get(:@request_store)
          expect(request_store.cancelled?(request_id)).to be true
        end
      end

      context "when request store operation fails" do
        before do
          request_store = transport.instance_variable_get(:@request_store)
          allow(request_store).to receive(:mark_cancelled).and_raise(StandardError.new("Store error"))
        end

        it "does not raise error on store failures" do
          expect {
            transport.send(:handle_cancellation, cancellation_message)
          }.not_to raise_error
        end
      end
    end

    describe "integration with request processing" do
      before do
        router.map("cancellable_method") do |message|
          request_context = Thread.current[:mcp_context]
          if request_context&.dig(:request_store)&.cancelled?(request_context[:request_id])
            raise ModelContextProtocol::Server::Cancellable::CancellationError, "Request was cancelled"
          end
          TestResponse[text: "completed"]
        end
      end

      it "handles cancellation notifications before routing to handlers" do
        $stdin.puts(JSON.generate(cancellation_message))
        $stdin.puts(JSON.generate({"jsonrpc" => "2.0", "id" => 1, "method" => "test_method"}))
        $stdin.rewind

        begin
          transport.handle
        rescue EOFError
          # Expected
        end

        $stdout.rewind
        output = $stdout.read
        response_lines = output.strip.split("\n")

        aggregate_failures do
          expect(response_lines.length).to eq(1)
          response_json = JSON.parse(response_lines[0])
          expect(response_json["id"]).to eq(1)
          expect(response_json["result"]).to eq({"text" => "foobar"})
        end
      end

      it "does not send response for cancellation notifications" do
        $stdin.puts(JSON.generate(cancellation_message))
        $stdin.rewind

        begin
          transport.handle
        rescue EOFError
          # Expected
        end

        $stdout.rewind
        output = $stdout.read

        expect(output.strip).to be_empty
      end
    end
  end

  describe "transport parameter passing" do
    let(:transport_passed) { [] }

    before do
      # Mock the router.route method to capture what transport is passed
      allow(router).to receive(:route) do |message, **kwargs|
        transport_passed << kwargs[:transport]
        TestResponse[text: "success"]
      end
    end

    context "when processing a regular request" do
      let(:request) { {"jsonrpc" => "2.0", "id" => 1, "method" => "test_method"} }

      before do
        $stdin.puts(JSON.generate(request))
        $stdin.rewind
      end

      it "passes the transport instance to router.route" do
        begin
          transport.handle
        rescue EOFError
          # Expected when stdin is exhausted
        end

        expect(transport_passed).to contain_exactly(transport)
      end

      it "passes transport along with request_store" do
        captured_kwargs = nil
        allow(router).to receive(:route) do |message, **kwargs|
          captured_kwargs = kwargs
          TestResponse[text: "success"]
        end

        begin
          transport.handle
        rescue EOFError
          # Expected when stdin is exhausted
        end

        expect(captured_kwargs).to include(
          request_store: transport.request_store,
          transport: transport
        )
      end
    end

    context "when processing multiple requests" do
      let(:request1) { {"jsonrpc" => "2.0", "id" => 1, "method" => "test_method"} }
      let(:request2) { {"jsonrpc" => "2.0", "id" => 2, "method" => "test_method"} }

      before do
        $stdin.puts(JSON.generate(request1))
        $stdin.puts(JSON.generate(request2))
        $stdin.rewind
      end

      it "passes transport to each router.route call" do
        begin
          transport.handle
        rescue EOFError
          # Expected when stdin is exhausted
        end

        expect(transport_passed).to contain_exactly(transport, transport)
      end
    end
  end
end
