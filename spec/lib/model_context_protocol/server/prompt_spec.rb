require "spec_helper"

RSpec.describe ModelContextProtocol::Server::Prompt do
  let(:client_logger) { double("client_logger") }
  let(:server_logger) { ModelContextProtocol::Server::ServerLogger.new }

  describe ".call" do
    context "when argument validation fails" do
      let(:invalid_arguments) { {foo: "bar"} }

      it "raises a ParameterValidationError" do
        expect {
          allow(client_logger).to receive(:info)
          TestPrompt.call(invalid_arguments, client_logger, server_logger)
        }.to raise_error(ModelContextProtocol::Server::ParameterValidationError)
      end
    end

    context "when argument validation succeeds" do
      let(:valid_arguments) { {undesirable_activity: "clean the garage"} }

      it "instantiates the prompt with the provided arguments" do
        allow(client_logger).to receive(:info)
        allow(client_logger).to receive(:info)
        expect(TestPrompt).to receive(:new).with(valid_arguments, client_logger, server_logger, {}).and_call_original
        TestPrompt.call(valid_arguments, client_logger, server_logger)
      end

      it "returns the response from the instance's call method" do
        allow(client_logger).to receive(:info)
        response = TestPrompt.call(valid_arguments, client_logger, server_logger)
        aggregate_failures do
          expect(response.messages.first[:content][:text]).to eq("My wife wants me to: clean the garage... Can you believe it?")
          expect(response.serialized[:description]).to eq("A prompt for brainstorming excuses to get out of something")
          expect(response.serialized[:title]).to eq("Brainstorm Excuses")
          expect(response.serialized[:messages]).to be_an(Array)
          expect(response.serialized[:messages].length).to eq(3)
        end
      end
    end
  end

  describe ".call with context" do
    let(:valid_arguments) { {undesirable_activity: "clean the garage"} }
    let(:context) { {"user_id" => "456", "environment" => "test"} }

    it "passes context to the instance" do
      allow(client_logger).to receive(:info)
      expect(TestPrompt).to receive(:new).with(valid_arguments, client_logger, server_logger, context).and_call_original
      TestPrompt.call(valid_arguments, client_logger, server_logger, context)
    end

    it "works with empty context" do
      allow(client_logger).to receive(:info)
      response = TestPrompt.call(valid_arguments, client_logger, server_logger, {})
      expect(response.messages.first[:content][:text]).to eq("My wife wants me to: clean the garage... Can you believe it?")
    end

    it "works when context is not provided" do
      allow(client_logger).to receive(:info)
      response = TestPrompt.call(valid_arguments, client_logger, server_logger)
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
        allow(client_logger).to receive(:info)
        expect { TestPrompt.new({foo: "bar"}, client_logger, server_logger) }.to raise_error(ArgumentError)
      end
    end

    context "when valid arguments are provided" do
      it "stores the arguments" do
        allow(client_logger).to receive(:info)
        prompt = TestPrompt.new({undesirable_activity: "clean the garage"}, client_logger, server_logger)
        expect(prompt.arguments).to eq({undesirable_activity: "clean the garage"})
      end

      it "stores context when provided" do
        context = {"user_id" => "123", "session" => "abc"}
        allow(client_logger).to receive(:info)
        prompt = TestPrompt.new({undesirable_activity: "clean the garage"}, client_logger, server_logger, context)
        expect(prompt.context).to eq(context)
      end

      it "defaults to empty hash when no context provided" do
        allow(client_logger).to receive(:info)
        prompt = TestPrompt.new({undesirable_activity: "clean the garage"}, client_logger, server_logger)
        expect(prompt.context).to eq({})
      end

      context "when optional arguments are provided" do
        it "stores the arguments" do
          allow(client_logger).to receive(:info)
          prompt = TestPrompt.new({undesirable_activity: "clean the garage", tone: "whiny"}, client_logger, server_logger)
          expect(prompt.arguments).to eq({undesirable_activity: "clean the garage", tone: "whiny"})
        end
      end
    end
  end

  describe ".define" do
    it "sets the class definition" do
      aggregate_failures do
        expect(TestPrompt.name).to eq("brainstorm_excuses")
        expect(TestPrompt.title).to eq("Brainstorm Excuses")
        expect(TestPrompt.description).to eq("A prompt for brainstorming excuses to get out of something")
      end
    end
  end

  describe "with_argument" do
    it "adds arguments to an array" do
      expect(TestPrompt.defined_arguments.size).to eq(2)
    end

    it "sets a required argument" do
      aggregate_failures do
        second_argument = TestPrompt.defined_arguments[1]
        expect(second_argument[:name]).to eq("undesirable_activity")
        expect(second_argument[:description]).to eq("The thing to get out of")
        expect(second_argument[:required]).to eq(true)
      end
    end

    it "sets a optional argument" do
      aggregate_failures do
        first_argument = TestPrompt.defined_arguments[0]
        expect(first_argument[:name]).to eq("tone")
        expect(first_argument[:description]).to eq("The general tone to be used in the generated excuses")
        expect(first_argument[:required]).to eq(false)
      end
    end

    it "sets an argument with a completion proc" do
      second_argument = TestPromptWithCompletionClass.defined_arguments[1]
      expect(second_argument[:completion]).to be(TestPromptWithCompletionClass::ToneCompletion)
    end

    it "sets an argument without a completion proc" do
      second_argument = TestPrompt.defined_arguments[1]
      expect(second_argument[:completion]).to be_nil
    end
  end

  describe ".definition" do
    it "returns class definition" do
      metadata = TestPrompt.definition
      expect(metadata[:name]).to eq("brainstorm_excuses")
      expect(metadata[:title]).to eq("Brainstorm Excuses")
      expect(metadata[:description]).to eq("A prompt for brainstorming excuses to get out of something")
      expect(metadata[:arguments].size).to eq(2)

      first_arg = metadata[:arguments][0]
      expect(first_arg[:name]).to eq("tone")
      expect(first_arg[:description]).to eq("The general tone to be used in the generated excuses")
      expect(first_arg[:required]).to eq(false)
      expect(first_arg[:completion]).to respond_to(:call)
      completion_result = first_arg[:completion].call("tone", "an")
      expect(completion_result.values).to eq(["angry"])

      second_arg = metadata[:arguments][1]
      expect(second_arg[:name]).to eq("undesirable_activity")
      expect(second_arg[:description]).to eq("The thing to get out of")
      expect(second_arg[:required]).to eq(true)
      expect(second_arg[:completion]).to be_nil
    end
  end

  describe "with class-based completion" do
    it "returns class definition with completion class" do
      metadata = TestPromptWithCompletionClass.definition
      expect(metadata[:name]).to eq("test_with_completion_class")
      expect(metadata[:title]).to eq("Test Prompt with Completion Class")
      expect(metadata[:description]).to eq("A test prompt that uses a completion class")
      expect(metadata[:arguments].size).to eq(2)

      completion_arg = metadata[:arguments][1]
      expect(completion_arg[:name]).to eq("completion_arg")
      expect(completion_arg[:description]).to eq("An argument with a completion class")
      expect(completion_arg[:required]).to eq(false)
      expect(completion_arg[:completion]).to be(TestPromptWithCompletionClass::ToneCompletion)
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
        first_argument_completion = TestPrompt.defined_arguments[0][:completion]
        argument_name = "tone"
        argument_value = "w"
        allow(first_argument_completion).to receive(:call).with(argument_name, argument_value).and_call_original
        TestPrompt.complete_for(argument_name, argument_value)
        expect(first_argument_completion).to have_received(:call).with(argument_name, argument_value)
      end
    end

    context "when argument name is a symbol" do
      it "converts the symbol to a string" do
        first_argument_completion = TestPrompt.defined_arguments[0][:completion]
        argument_name = "tone"
        argument_value = "w"
        allow(first_argument_completion).to receive(:call).with(argument_name, argument_value).and_call_original
        TestPrompt.complete_for(argument_name.to_sym, argument_value)
        expect(first_argument_completion).to have_received(:call).with(argument_name, argument_value)
      end
    end
  end

  describe "optional title field" do
    let(:prompt_without_title) do
      Class.new(ModelContextProtocol::Server::Prompt) do
        define do
          name "test_prompt"
          description "A test prompt without title"
        end

        def call
          respond_with messages: []
        end
      end
    end

    it "does not include title in definition when not provided" do
      metadata = prompt_without_title.definition
      expect(metadata).not_to have_key(:title)
    end

    it "does not include title in serialized response when not provided" do
      double("logger")
      response = prompt_without_title.call({}, client_logger, server_logger)
      expect(response.serialized).not_to have_key(:title)
    end
  end

  describe "array-based completions" do
    let(:test_array_prompt) { TestPrompt }

    it "creates a completion from an array of values" do
      completion = test_array_prompt.defined_arguments.first[:completion]
      expect(completion).to respond_to(:call)
    end

    it "filters completion values based on input" do
      result = test_array_prompt.complete_for("tone", "an")
      expect(result.values).to eq(["angry"])
      expect(result.total).to eq(1)
      expect(result.hasMore).to be(false)
    end

    it "returns multiple matches when appropriate" do
      result = test_array_prompt.complete_for("tone", "n")
      expect(result.values).to include("whiny", "angry", "nervous", "sneaky")
      expect(result.total).to eq(4)
    end

    it "returns empty array when no matches" do
      result = test_array_prompt.complete_for("tone", "xyz")
      expect(result.values).to eq([])
      expect(result.total).to eq(0)
    end
  end

  describe "server logger integration" do
    it "calls server_logger during execution" do
      allow(client_logger).to receive(:info)
      aggregate_failures do
        expect(server_logger).to receive(:debug).with(a_string_matching(/Prompt called with arguments:/))
        expect(server_logger).to receive(:info).with("Generating excuse brainstorming prompt")
      end

      TestPrompt.call({undesirable_activity: "clean the garage"}, client_logger, server_logger)
    end

    it "uses context values in server logging" do
      allow(client_logger).to receive(:info)
      context = {user_id: "test-user-456"}
      aggregate_failures do
        expect(server_logger).to receive(:debug).with(a_string_matching(/Prompt called with arguments:/))
        expect(server_logger).to receive(:info).with("Generating excuse brainstorming prompt")
        expect(server_logger).to receive(:info).with("User test-user-456 is generating excuses")
      end

      TestPrompt.call({undesirable_activity: "clean the garage"}, client_logger, server_logger, context)
    end

    it "handles empty context gracefully in server logging" do
      allow(client_logger).to receive(:info)
      aggregate_failures do
        expect(server_logger).to receive(:debug).with(a_string_matching(/Prompt called with arguments:/))
        expect(server_logger).to receive(:info).with("Generating excuse brainstorming prompt")
      end

      TestPrompt.call({undesirable_activity: "clean the garage"}, client_logger, server_logger, {})
    end
  end
end
