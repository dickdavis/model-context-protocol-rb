require "spec_helper"

RSpec.describe ModelContextProtocol::Server::Prompt do
  describe ".call" do
    context "when argument validation fails" do
      let(:invalid_arguments) { {foo: "bar"} }

      it "raises a ParameterValidationError" do
        expect {
          TestPrompt.call(invalid_arguments, double("logger"))
        }.to raise_error(ModelContextProtocol::Server::ParameterValidationError)
      end
    end

    context "when argument validation succeeds" do
      let(:valid_arguments) { {undesirable_activity: "clean the garage"} }

      it "instantiates the prompt with the provided arguments" do
        logger = double("logger")
        expect(TestPrompt).to receive(:new).with(valid_arguments, logger, {}).and_call_original
        TestPrompt.call(valid_arguments, logger)
      end

      it "returns the response from the instance's call method" do
        logger = double("logger")
        response = TestPrompt.call(valid_arguments, logger)
        aggregate_failures do
          expect(response.messages.first[:content][:text]).to eq("My wife wants me to: clean the garage... Can you believe it?")
          expect(response.serialized[:description]).to eq("A prompt for brainstorming excuses to get out of something")
          expect(response.serialized[:messages]).to be_an(Array)
          expect(response.serialized[:messages].length).to eq(5)
        end
      end
    end
  end

  describe ".call with context" do
    let(:valid_arguments) { {undesirable_activity: "clean the garage"} }
    let(:context) { {"user_id" => "456", "environment" => "test"} }

    it "passes context to the instance" do
      logger = double("logger")
      expect(TestPrompt).to receive(:new).with(valid_arguments, logger, context).and_call_original
      TestPrompt.call(valid_arguments, logger, context)
    end

    it "works with empty context" do
      logger = double("logger")
      response = TestPrompt.call(valid_arguments, logger, {})
      expect(response.messages.first[:content][:text]).to eq("My wife wants me to: clean the garage... Can you believe it?")
    end

    it "works when context is not provided" do
      logger = double("logger")
      response = TestPrompt.call(valid_arguments, logger)
      expect(response.messages.first[:content][:text]).to eq("My wife wants me to: clean the garage... Can you believe it?")
    end
  end

  describe "#initialize" do
    context "when no arguments are provided" do
      it "raises an ArgumentError" do
        expect { TestPrompt.new }.to raise_error(ArgumentError)
      end
    end

    context "when invalid arguments are provided" do
      it "raises an ArgumentError" do
        expect { TestPrompt.new({foo: "bar"}, double("logger")) }.to raise_error(ArgumentError)
      end
    end

    context "when valid arguments are provided" do
      it "stores the arguments" do
        logger = double("logger")
        prompt = TestPrompt.new({undesirable_activity: "clean the garage"}, logger)
        expect(prompt.params).to eq({undesirable_activity: "clean the garage"})
      end

      it "stores context when provided" do
        context = {"user_id" => "123", "session" => "abc"}
        logger = double("logger")
        prompt = TestPrompt.new({undesirable_activity: "clean the garage"}, logger, context)
        expect(prompt.context).to eq(context)
      end

      it "defaults to empty hash when no context provided" do
        logger = double("logger")
        prompt = TestPrompt.new({undesirable_activity: "clean the garage"}, logger)
        expect(prompt.context).to eq({})
      end

      context "when optional arguments are provided" do
        it "stores the arguments" do
          logger = double("logger")
          prompt = TestPrompt.new({undesirable_activity: "clean the garage", tone: "whiny"}, logger)
          expect(prompt.params).to eq({undesirable_activity: "clean the garage", tone: "whiny"})
        end
      end
    end
  end

  describe ".with_metadata" do
    it "sets the class metadata" do
      aggregate_failures do
        expect(TestPrompt.name).to eq("brainstorm_excuses")
        expect(TestPrompt.description).to eq("A prompt for brainstorming excuses to get out of something")
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
        expect(first_argument[:name]).to eq("undesirable_activity")
        expect(first_argument[:description]).to eq("The thing to get out of")
        expect(first_argument[:required]).to eq(true)
      end
    end

    it "sets a optional argument" do
      aggregate_failures do
        second_argument = TestPrompt.arguments[1]
        expect(second_argument[:name]).to eq("tone")
        expect(second_argument[:description]).to eq("The general tone to be used in the generated excuses")
        expect(second_argument[:required]).to eq(false)
      end
    end

    it "sets an argument with a completion proc" do
      second_argument = TestPrompt.arguments[1]
      expect(second_argument[:completion]).to be(TestPrompt::ToneCompletion)
    end

    it "sets an argument without a completion proc" do
      first_argument = TestPrompt.arguments[0]
      expect(first_argument[:completion]).to be_nil
    end
  end

  describe ".metadata" do
    it "returns class metadata" do
      metadata = TestPrompt.metadata
      expect(metadata[:name]).to eq("brainstorm_excuses")
      expect(metadata[:description]).to eq("A prompt for brainstorming excuses to get out of something")
      expect(metadata[:arguments].size).to eq(2)

      first_arg = metadata[:arguments][0]
      expect(first_arg[:name]).to eq("undesirable_activity")
      expect(first_arg[:description]).to eq("The thing to get out of")
      expect(first_arg[:required]).to eq(true)
      expect(first_arg[:completion]).to be_nil

      second_arg = metadata[:arguments][1]
      expect(second_arg[:name]).to eq("tone")
      expect(second_arg[:description]).to eq("The general tone to be used in the generated excuses")
      expect(second_arg[:required]).to eq(false)
      expect(second_arg[:completion]).to be(TestPrompt::ToneCompletion)
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
        second_argument_completion = TestPrompt.arguments[1][:completion]
        argument_name = "tone"
        argument_value = "w"
        allow(second_argument_completion).to receive(:call).with(argument_name, argument_value).and_call_original
        TestPrompt.complete_for(argument_name, argument_value)
        expect(second_argument_completion).to have_received(:call).with(argument_name, argument_value)
      end
    end

    context "when argument name is a symbol" do
      it "converts the symbol to a string" do
        second_argument_completion = TestPrompt.arguments[1][:completion]
        argument_name = "tone"
        argument_value = "w"
        allow(second_argument_completion).to receive(:call).with(argument_name, argument_value).and_call_original
        TestPrompt.complete_for(argument_name.to_sym, argument_value)
        expect(second_argument_completion).to have_received(:call).with(argument_name, argument_value)
      end
    end
  end
end
