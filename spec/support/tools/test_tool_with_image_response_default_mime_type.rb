class TestToolWithImageResponseDefaultMimeType < ModelContextProtocol::Server::Tool
  with_metadata do
    {
      name: "image-generator",
      description: "Generates a simple image based on a topic",
      inputSchema: {
        type: "object",
        properties: {
          topic: {
            type: "string",
            description: "Topic to generate an image about"
          }
        },
        required: ["topic"]
      }
    }
  end

  def call
    # In a real implementation, we would generate an actual image based on the topic
    # Here we just return a placeholder
    respond_with :image, data: "base64encodeddata"
  end
end
