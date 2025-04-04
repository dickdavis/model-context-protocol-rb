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
