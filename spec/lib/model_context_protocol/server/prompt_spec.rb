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

      it "instantiates the prompt with the provided parameters" do
        expect(TestPrompt).to receive(:new).with(valid_params).and_call_original
        TestPrompt.call(valid_params)
      end

      it "returns the response from the instance's call method" do
        response = TestPrompt.call(valid_params)
        aggregate_failures do
          expect(response.messages).to eq(
            [
              {
                role: "user",
                content: {
                  type: "text",
                  text: "Do this: Hello, world!"
                }
              }
            ]
          )
          expect(response.serialized).to eq(
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
        prompt = TestPrompt.new({"message" => "Hello, world!"})
        expect(prompt.params).to eq({"message" => "Hello, world!"})
      end

      context "when optional parameters are provided" do
        it "stores the parameters" do
          prompt = TestPrompt.new({"message" => "Hello, world!", "other" => "Other thing"})
          expect(prompt.params).to eq({"message" => "Hello, world!", "other" => "Other thing"})
        end
      end
    end
  end

  describe ".with_metadata" do
    it "sets the class metadata" do
      aggregate_failures do
        expect(TestPrompt.name).to eq("test_prompt")
        expect(TestPrompt.description).to eq("A test prompt")
      end
    end
  end

  describe "with_argument" do
    it "adds arguments to an array" do
      expect(TestPrompt.arguments.size).to eq(2)
    end

    it "sets a required argument" do
      aggregate_failures do
        first_argument = TestPrompt.arguments[0]
        expect(first_argument[:name]).to eq("message")
        expect(first_argument[:description]).to eq("The thing to do")
        expect(first_argument[:required]).to eq(true)
      end
    end

    it "sets a optional argument" do
      aggregate_failures do
        second_argument = TestPrompt.arguments[1]
        expect(second_argument[:name]).to eq("other")
        expect(second_argument[:description]).to eq("Another thing to do")
        expect(second_argument[:required]).to eq(false)
      end
    end

    it "sets an argument with a completion proc" do
      first_argument = TestPrompt.arguments[0]
      expect(first_argument[:completion]).to be(TestCompletion)
    end

    it "sets an argument without a completion proc" do
      second_argument = TestPrompt.arguments[1]
      expect(second_argument[:completion]).to be_nil
    end
  end

  describe ".metadata" do
    it "returns class metadata" do
      metadata = TestPrompt.metadata
      expect(metadata[:name]).to eq("test_prompt")
      expect(metadata[:description]).to eq("A test prompt")
      expect(metadata[:arguments].size).to eq(2)

      first_arg = metadata[:arguments][0]
      expect(first_arg[:name]).to eq("message")
      expect(first_arg[:description]).to eq("The thing to do")
      expect(first_arg[:required]).to eq(true)
      expect(first_arg[:completion]).to be(TestCompletion)

      second_arg = metadata[:arguments][1]
      expect(second_arg[:name]).to eq("other")
      expect(second_arg[:description]).to eq("Another thing to do")
      expect(second_arg[:required]).to eq(false)
      expect(second_arg[:completion]).to be_nil
    end
  end

  describe ".complete_for" do
    context "when the argument does not exist" do
      it "returns nil" do
        result = TestPrompt.complete_for("nonexistent_argument", "f")
        expect(result).to be_a(ModelContextProtocol::Server::NullCompletion::Response)
      end
    end

    context "when the argument does not have a completion" do
      it "returns nil" do
        result = TestPrompt.complete_for("other_message", "f")
        expect(result).to be_a(ModelContextProtocol::Server::NullCompletion::Response)
      end
    end

    context "when the argument has a completion proc" do
      it "calls the completion proc with the argument name" do
        first_argument_completion = TestPrompt.arguments[0][:completion]
        argument_name = "message"
        argument_value = "f"
        allow(first_argument_completion).to receive(:call).with(argument_name, argument_value).and_call_original
        TestPrompt.complete_for(argument_name, argument_value)
        expect(first_argument_completion).to have_received(:call).with(argument_name, argument_value)
      end
    end

    context "when argument name is a symbol" do
      it "converts the symbol to a string" do
        first_argument_completion = TestPrompt.arguments[0][:completion]
        argument_name = "message"
        argument_value = "f"
        allow(first_argument_completion).to receive(:call).with(argument_name, argument_value).and_call_original
        TestPrompt.complete_for(argument_name.to_sym, argument_value)
        expect(first_argument_completion).to have_received(:call).with(argument_name, argument_value)
      end
    end
  end
end
