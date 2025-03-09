require "spec_helper"

RSpec.describe ModelContextProtocol::Server::Tool do
  describe ".call" do
    context "when input schema validation fails" do
      let(:invalid_params) { {"foo" => "bar"} }

      it "raises a SchemaValidationError" do
        expect {
          TestTool.call(invalid_params)
        }.to raise_error(ModelContextProtocol::Server::SchemaValidationError)
      end
    end

    context "when input schema validation succeeds" do
      let(:valid_params) { {"message" => "Hello, world!"} }

      it "instantiates the tool with the provided parameters" do
        expect(TestTool).to receive(:new).with(valid_params).and_call_original
        TestTool.call(valid_params)
      end

      it "returns the response from the instance's call method" do
        response = TestTool.call(valid_params)
        expect(response).to eq(
          content: [
            {
              type: "text",
              text: "You said: Hello, world!"
            }
          ],
          isError: false
        )
      end

      context "when an unexpected error occurs" do
        before do
          allow_any_instance_of(TestTool).to receive(:call).and_raise("Test error")
        end

        it "returns an error response" do
          response = TestTool.call(valid_params)
          expect(response).to eq(
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

  describe "#initialize" do
    it "validates the parameters against the schema" do
      expect(JSON::Validator).to receive(:validate!).with(
        TestTool.input_schema,
        {"message" => "Hello, world!"}
      )
      TestTool.new({"message" => "Hello, world!"})
    end

    it "stores the parameters" do
      tool = TestTool.new({"message" => "Hello, world!"})
      expect(tool.params).to eq({"message" => "Hello, world!"})
    end
  end

  describe "data objects for responses" do
    describe "TextResponse" do
      it "formats text responses correctly" do
        response = described_class::TextResponse[text: "Hello"]
        expect(response.serialized).to eq(
          content: [
            {
              type: "text",
              text: "Hello"
            }
          ],
          isError: false
        )
      end
    end

    describe "ImageResponse" do
      it "formats image responses correctly" do
        response = described_class::ImageResponse[data: "base64data", mime_type: "image/jpeg"]
        expect(response.serialized).to eq(
          content: [
            {
              type: "image",
              data: "base64data",
              mimeType: "image/jpeg"
            }
          ],
          isError: false
        )
      end

      it "defaults to PNG mime type" do
        response = described_class::ImageResponse[data: "base64data"]
        expect(response.serialized).to eq(
          content: [
            {
              type: "image",
              data: "base64data",
              mimeType: "image/png"
            }
          ],
          isError: false
        )
      end
    end

    describe "ResourceResponse" do
      it "formats resource responses correctly" do
        response = described_class::ResourceResponse[uri: "resource://test", text: "content", mime_type: "text/markdown"]
        expect(response.serialized).to eq(
          content: [
            type: "resource",
            resource: {
              uri: "resource://test",
              mimeType: "text/markdown",
              text: "content"
            }
          ],
          isError: false
        )
      end

      it "defaults to text/plain mime type" do
        response = described_class::ResourceResponse[uri: "resource://test", text: "content"]
        expect(response.serialized).to eq(
          content: [
            type: "resource",
            resource: {
              uri: "resource://test",
              mimeType: "text/plain",
              text: "content"
            }
          ],
          isError: false
        )
      end
    end

    describe "ToolErrorResponse" do
      it "formats error responses correctly" do
        response = described_class::ToolErrorResponse[text: "Something went wrong"]
        expect(response.serialized).to eq(
          content: [
            {
              type: "text",
              text: "Something went wrong"
            }
          ],
          isError: true
        )
      end
    end
  end

  describe "with_metadata" do
    it "sets the class metadata" do
      expect(TestTool.name).to eq("Test Tool")
      expect(TestTool.description).to eq("A test tool")
      expect(TestTool.input_schema).to eq(
        type: "object",
        properties: {
          message: {
            type: "string"
          }
        },
        required: ["message"]
      )
    end
  end

  describe "metadata" do
    it "returns class metadata" do
      expect(TestTool.metadata).to eq(
        name: "Test Tool",
        description: "A test tool",
        inputSchema: {
          type: "object",
          properties: {
            message: {
              type: "string"
            }
          },
          required: ["message"]
        }
      )
    end
  end
end
