class TestTool < ModelContextProtocol::Server::Tool
  with_metadata do
    {
      name: "Test Tool",
      description: "A test tool",
      inputSchema: {
        type: "object",
        properties: {
          message: {
            type: "string"
          }
        },
        required: ["message"]
      }
    }
  end

  def call
    TextResponse[text: "You said: #{params["message"]}"]
  end
end
