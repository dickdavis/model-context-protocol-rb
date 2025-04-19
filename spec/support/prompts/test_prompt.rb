class TestPrompt < ModelContextProtocol::Server::Prompt
  with_metadata do
    name "test_prompt"
    description "A test prompt"
  end

  with_argument do
    name "message"
    description "The thing to do"
    required true
    completion TestCompletion
  end

  with_argument do
    name "other"
    description "Another thing to do"
    required false
  end

  def call
    messages = [
      {
        role: "user",
        content: {
          type: "text",
          text: "Do this: #{params["message"]}"
        }
      }
    ]

    respond_with messages: messages
  end
end
