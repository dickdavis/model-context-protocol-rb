class TestToolWithResourceResponse < ModelContextProtocol::Server::Tool
  with_metadata do
    {
      name: "code-generator",
      description: "Generates code in the specified language",
      inputSchema: {
        type: "object",
        properties: {
          language: {
            type: "string",
            description: "Programming language"
          },
          functionality: {
            type: "string",
            description: "What the code should do"
          }
        },
        required: ["language", "functionality"]
      }
    }
  end

  def call
    # Map language to mime type
    mime_type = case params["language"].downcase
    when "python"
      "text/x-python"
    when "javascript"
      "application/javascript"
    when "ruby"
      "text/x-ruby"
    else
      "text/plain"
    end

    # In a real implementation, we would generate actual code
    generated_code = "// Generated #{params["language"]} code for: #{params["functionality"]}\n// This is just a placeholder"
    respond_with :resource, uri: "code://generated/code", text: generated_code, mime_type:
  end
end
