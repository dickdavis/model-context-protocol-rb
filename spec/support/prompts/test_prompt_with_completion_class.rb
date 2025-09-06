class TestPromptWithCompletionClass < ModelContextProtocol::Server::Prompt
  ToneCompletion = ModelContextProtocol::Server::Completion.define do
    hints = ["whiny", "angry", "callous", "desperate", "nervous", "sneaky"]
    values = hints.grep(/#{argument_value}/)

    respond_with values:
  end

  define do
    name "test_with_completion_class"
    title "Test Prompt with Completion Class"
    description "A test prompt that uses a completion class"

    argument do
      name "required_arg"
      description "A required argument"
      required true
    end

    argument do
      name "completion_arg"
      description "An argument with a completion class"
      required false
      completion ToneCompletion
    end
  end

  def call
    respond_with messages: [
      {
        role: "user",
        content: {
          type: "text",
          text: "Test message with #{arguments[:required_arg]}"
        }
      }
    ]
  end
end
