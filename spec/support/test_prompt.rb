class TestPrompt < ModelContextProtocol::Server::Prompt
  with_metadata do
    {
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
    }
  end

  def call
    TextResponse[text: "Do this: #{params["message"]}"]
  end
end
