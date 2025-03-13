require "spec_helper"

RSpec.describe ModelContextProtocol::Server::Tool do
  describe ".call" do
    context "when input schema validation fails" do
      let(:invalid_params) { {"foo" => "bar"} }

      it "raises a ParameterValidationError" do
        expect {
          TestToolWithTextResponse.call(invalid_params)
        }.to raise_error(ModelContextProtocol::Server::ParameterValidationError)
      end
    end

    context "when input schema validation succeeds" do
      let(:valid_params) { {"text" => "Hello, world!"} }

      it "instantiates the tool with the provided parameters" do
        expect(TestToolWithTextResponse).to receive(:new).with(valid_params).and_call_original
        TestToolWithTextResponse.call(valid_params)
      end

      it "returns the response from the instance's call method" do
        response = TestToolWithTextResponse.call(valid_params)
        aggregate_failures do
          expect(response.text).to eq("Summary of your text: Hello, world!...")
          expect(response.serialized).to eq(
            content: [
              {
                type: "text",
                text: "Summary of your text: Hello, world!..."
              }
            ],
            isError: false
          )
        end
      end

      context "when an unexpected error occurs" do
        before do
          allow_any_instance_of(TestToolWithTextResponse).to receive(:call).and_raise("Test error")
        end

        it "returns an error response" do
          response = TestToolWithTextResponse.call(valid_params)
          aggregate_failures do
            expect(response.text).to eq("Test error")
            expect(response.serialized).to eq(
              content: [
                {
                  type: "text",
                  text: "Test error"
                }
              ],
              isError: true
            )
          end
        end
      end
    end
  end

  describe "#initialize" do
    it "validates the parameters against the schema" do
      expect(JSON::Validator).to receive(:validate!).with(
        TestToolWithTextResponse.input_schema,
        {"text" => "Hello, world!"}
      )
      TestToolWithTextResponse.new({"text" => "Hello, world!"})
    end

    it "stores the parameters" do
      tool = TestToolWithTextResponse.new({"text" => "Hello, world!"})
      expect(tool.params).to eq({"text" => "Hello, world!"})
    end
  end

  describe "responses" do
    describe "text response" do
      it "formats text response correctly" do
        params = {"text" => "Hello"}
        response = TestToolWithTextResponse.call(params)
        expect(response.serialized).to eq(
          content: [
            {
              type: "text",
              text: "Summary of your text: Hello..."
            }
          ],
          isError: false
        )
      end
    end

    describe "image response" do
      it "formats image responses correctly" do
        params = {"chart_type" => "bar", "format" => "jpg"}
        response = TestToolWithImageResponse.call(params)
        expect(response.serialized).to eq(
          content: [
            {
              type: "image",
              data: "base64encodeddata",
              mimeType: "image/jpeg"
            }
          ],
          isError: false
        )
      end

      it "defaults to PNG mime type" do
        params = {"topic" => "foobar"}
        response = TestToolWithImageResponseDefaultMimeType.call(params)
        expect(response.serialized).to eq(
          content: [
            {
              type: "image",
              data: "base64encodeddata",
              mimeType: "image/png"
            }
          ],
          isError: false
        )
      end
    end

    describe "resource response" do
      it "formats resource responses correctly" do
        params = {"language" => "ruby", "functionality" => "foobar"}
        response = TestToolWithResourceResponse.call(params)
        expect(response.serialized).to eq(
          content: [
            type: "resource",
            resource: {
              uri: "code://generated/code",
              mimeType: "text/x-ruby",
              text: "// Generated ruby code for: foobar\n// This is just a placeholder"
            }
          ],
          isError: false
        )
      end

      it "defaults to text/plain mime type" do
        params = {"title" => "foobar", "content" => "baz"}
        response = TestToolWithResourceResponseDefaultMimeType.call(params)
        expect(response.serialized).to eq(
          content: [
            type: "resource",
            resource: {
              uri: "note://notes/foobar",
              mimeType: "text/plain",
              text: "baz"
            }
          ],
          isError: false
        )
      end
    end

    describe "tool error response" do
      it "formats error responses correctly" do
        params = {"api_endpoint" => "http://example.com", "method" => "GET"}
        response = TestToolWithToolErrorResponse.call(params)
        expect(response.serialized).to eq(
          content: [
            {
              type: "text",
              text: "Failed to call API at http://example.com: Connection timed out"
            }
          ],
          isError: true
        )
      end
    end
  end

  describe "with_metadata" do
    it "sets the class metadata" do
      aggregate_failures do
        expect(TestToolWithTextResponse.name).to eq("text-summarizer")
        expect(TestToolWithTextResponse.description).to eq("Summarizes provided text")
        expect(TestToolWithTextResponse.input_schema).to eq(
          type: "object",
          properties: {
            text: {
              type: "string"
            }
          },
          required: ["text"]
        )
      end
    end
  end

  describe "metadata" do
    it "returns class metadata" do
      expect(TestToolWithTextResponse.metadata).to eq(
        name: "text-summarizer",
        description: "Summarizes provided text",
        inputSchema: {
          type: "object",
          properties: {
            text: {
              type: "string"
            }
          },
          required: ["text"]
        }
      )
    end
  end
end
