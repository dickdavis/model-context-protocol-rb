require "spec_helper"

TestResponse = Data.define(:text) do
  def serialized
    {text:}
  end
end

RSpec.describe ModelContextProtocol::Server::StdioTransport do
  subject(:transport) { described_class.new(logger: logger, router: router) }

  let(:logger) { Logger.new(StringIO.new) }
  let(:router) { ModelContextProtocol::Server::Router.new }

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
        allow(logger).to receive(:error)

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
          expect(logger).to have_received(:error).with(/Parser error/)
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
        allow(logger).to receive(:error)

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
          expect(logger).to have_received(:error).with(/Validation error: Invalid parameters/)
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
        allow(logger).to receive(:error)

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
          expect(logger).to have_received(:error).with(/Internal error: Something went wrong/)
          expect(logger).to have_received(:error).with(kind_of(Array)) # backtrace
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
end
