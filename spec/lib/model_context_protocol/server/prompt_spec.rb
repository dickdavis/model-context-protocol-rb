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
          description: "A test prompt",
          messages: [
            {
              role: "user",
              content: {
                type: "text",
                text: "Do this: Hello, world!"
              }
            }
          ]
        )
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
    describe "Response" do
      it "formats responses correctly" do
        messages = [
          {
            role: "user",
            content: {
              type: "text",
              text: "This is a test"
            }
          }
        ]
        response = described_class::Response[messages:, prompt: TestPrompt.new({"message" => "Hello, world!"})]
        expect(response.serialized).to eq(
          description: "A test prompt",
          messages: [
            {
              role: "user",
              content: {
                type: "text",
                text: "This is a test"
              }
            }
          ]
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
