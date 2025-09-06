class TestArrayCompletionPrompt < ModelContextProtocol::Server::Prompt
  define do
    name "test_array_completion"
    description "A prompt to test array-based completions"

    argument do
      name "flavor"
      description "The flavor preference"
      required false
      completion ["vanilla", "chocolate", "strawberry", "mint", "caramel"]
    end
  end

  def call
    respond_with messages: [
      {
        role: "user",
        content: {
          type: "text",
          text: "You chose #{arguments[:flavor]} flavor!"
        }
      }
    ]
  end
end
