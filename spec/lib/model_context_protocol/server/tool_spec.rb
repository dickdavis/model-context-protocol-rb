require "spec_helper"

RSpec.describe ModelContextProtocol::Server::Tool do
  describe ".call" do
    context "when input schema validation fails" do
      let(:invalid_arguments) { {foo: "bar"} }

      it "raises a ParameterValidationError" do
        expect {
          TestToolWithTextResponse.call(invalid_arguments)
        }.to raise_error(ModelContextProtocol::Server::ParameterValidationError)
      end
    end

    context "when input schema validation succeeds" do
      let(:valid_arguments) { {number: "21"} }

      it "instantiates the tool with the provided arguments" do
        expect(TestToolWithTextResponse).to receive(:new).with(valid_arguments, {}).and_call_original
        TestToolWithTextResponse.call(valid_arguments)
      end

      it "returns the response from the instance's call method" do
        response = TestToolWithTextResponse.call(valid_arguments)
        aggregate_failures do
          expect(response.text).to eq("21 doubled is 42")
          expect(response.serialized).to eq(
            content: [
              {
                type: "text",
                text: "21 doubled is 42"
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
          response = TestToolWithTextResponse.call(valid_arguments)
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

    it "stores the arguments" do
      tool = TestToolWithTextResponse.new({number: "42"})
      expect(tool.params).to eq({number: "42"})
    end

    it "stores context when provided" do
      context = {"user_id" => "123", "session" => "abc"}
      tool = TestToolWithTextResponse.new({"number" => "42"}, context)
      expect(tool.context).to eq(context)
    end

    it "defaults to empty hash when no context provided" do
      tool = TestToolWithTextResponse.new({number: "42"})
      expect(tool.context).to eq({})
    end
  end

  describe ".call with context" do
    let(:valid_arguments) { {number: "21"} }
    let(:context) { {user_id: "123456"} }

    it "passes context to the instance" do
      allow(TestToolWithTextResponse).to receive(:new).with(valid_arguments, context).and_call_original
      response = TestToolWithTextResponse.call(valid_arguments, context)
      aggregate_failures do
        expect(TestToolWithTextResponse).to have_received(:new).with(valid_arguments, context)
        expect(response.text).to eq("User 123456, 21 doubled is 42")
      end
    end

    it "works with empty context" do
      response = TestToolWithTextResponse.call(valid_arguments, {})
      expect(response.text).to eq("21 doubled is 42")
    end

    it "works when context is not provided" do
      response = TestToolWithTextResponse.call(valid_arguments)
      expect(response.text).to eq("21 doubled is 42")
    end
  end

  describe "responses" do
    describe "text response" do
      it "formats text response correctly" do
        arguments = {number: "21"}
        response = TestToolWithTextResponse.call(arguments)
        expect(response.serialized).to eq(
          content: [
            {
              type: "text",
              text: "21 doubled is 42"
            }
          ],
          isError: false
        )
      end
    end

    describe "image response" do
      it "formats image responses correctly" do
        arguments = {chart_type: "bar", format: "jpg"}
        response = TestToolWithImageResponse.call(arguments)
        expect(response.serialized).to eq(
          content: [
            {
              type: "image",
              data: "dGVzdA==",
              mimeType: "image/jpeg"
            }
          ],
          isError: false
        )
      end

      it "defaults to PNG mime type" do
        arguments = {chart_type: "bar"}
        response = TestToolWithImageResponseDefaultMimeType.call(arguments)
        expect(response.serialized).to eq(
          content: [
            {
              type: "image",
              data: "dGVzdA==",
              mimeType: "image/png"
            }
          ],
          isError: false
        )
      end
    end

    describe "resource response" do
      it "formats resource responses correctly" do
        arguments = {title: "Foobar"}
        response = TestToolWithResourceResponse.call(arguments)
        expect(response.serialized).to eq(
          content: [
            type: "resource",
            resource: {
              uri: "resource://document/foobar",
              mimeType: "application/rtf",
              text: "richtextdata"
            }
          ],
          isError: false
        )
      end

      it "defaults to text/plain mime type" do
        arguments = {title: "foobar", content: "baz"}
        response = TestToolWithResourceResponseDefaultMimeType.call(arguments)
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
        arguments = {api_endpoint: "http://example.com", method: "GET"}
        response = TestToolWithToolErrorResponse.call(arguments)
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
        expect(TestToolWithTextResponse.name).to eq("double")
        expect(TestToolWithTextResponse.description).to eq("Doubles the provided number")
        expect(TestToolWithTextResponse.input_schema).to eq(
          type: "object",
          properties: {
            number: {
              type: "string"
            }
          },
          required: ["number"]
        )
      end
    end
  end

  describe "metadata" do
    it "returns class metadata" do
      expect(TestToolWithTextResponse.metadata).to eq(
        name: "double",
        description: "Doubles the provided number",
        inputSchema: {
          type: "object",
          properties: {
            number: {
              type: "string"
            }
          },
          required: ["number"]
        }
      )
    end
  end
end
