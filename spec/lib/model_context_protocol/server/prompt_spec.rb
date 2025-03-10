require "spec_helper"

RSpec.describe ModelContextProtocol::Server::Prompt do
  describe ".call" do
    context "when parameter validation fails" do
      let(:invalid_params) { {"foo" => "bar"} }

      it "raises a ParameterValidationError" do
        expect {
          TestPrompt.call(invalid_params)
        }.to raise_error(ModelContextProtocol::Server::ParameterValidationError)
      end
    end

    context "when parameter validation succeeds" do
      let(:valid_params) { {"message" => "Hello, world!"} }

      it "instantiates the tool with the provided parameters" do
        expect(TestPrompt).to receive(:new).with(valid_params).and_call_original
        TestPrompt.call(valid_params)
      end

      it "returns the response from the instance's call method" do
        response = TestPrompt.call(valid_params)
        expect(response).to eq(
          content: [
            {
              type: "text",
              text: "Do this: Hello, world!"
            }
          ],
          isError: false
        )
      end

      context "when an unexpected error occurs" do
        before do
          allow_any_instance_of(TestPrompt).to receive(:call).and_raise(StandardError, "Test error")
        end

        it "returns an error response" do
          response = TestPrompt.call(valid_params)
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
    context "when no parameters are provided" do
      it "raises an ArgumentError" do
        expect { TestPrompt.new }.to raise_error(ArgumentError)
      end
    end

    context "when invalid parameters are provided" do
      it "raises an ArgumentError" do
        expect { TestPrompt.new({"foo" => "bar"}) }.to raise_error(ArgumentError)
      end
    end

    context "when valid parameters are provided" do
      it "stores the parameters" do
        tool = TestPrompt.new({"message" => "Hello, world!"})
        expect(tool.params).to eq({"message" => "Hello, world!"})
      end

      context "when optional parameters are provided" do
        it "stores the parameters" do
          tool = TestPrompt.new({"message" => "Hello, world!", "other" => "Other thing"})
          expect(tool.params).to eq({"message" => "Hello, world!", "other" => "Other thing"})
        end
      end
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

    describe "PromptErrorResponse" do
      it "formats error responses correctly" do
        response = described_class::PromptErrorResponse[text: "Something went wrong"]
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
      aggregate_failures do
        expect(TestPrompt.name).to eq("Test Prompt")
        expect(TestPrompt.description).to eq("A test prompt")
        expect(TestPrompt.arguments).to eq(
          [
            {
              name: "message",
              description: "The thing to do",
              required: true
            },
            {
              name: "other",
              description: "Another thing to do",
              required: false
            }
          ]
        )
      end
    end
  end

  describe "metadata" do
    it "returns class metadata" do
      expect(TestPrompt.metadata).to eq(
        name: "Test Prompt",
        description: "A test prompt",
        arguments: [
          {
            name: "message",
            description: "The thing to do",
            required: true
          },
          {
            name: "other",
            description: "Another thing to do",
            required: false
          }
        ]
      )
    end
  end
end
