class TestToolWithTextResponse < ModelContextProtocol::Server::Tool
  with_metadata do
    {
      name: "text-summarizer",
      description: "Summarizes provided text",
      inputSchema: {
        type: "object",
        properties: {
          text: {
            type: "string"
          }
        },
        required: ["text"]
      }
    }
  end

  def call
    respond_with :text, text: "Summary of your text: #{params["text"][0..30]}..."
  end
end
