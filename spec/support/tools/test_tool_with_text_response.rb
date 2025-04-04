class TestToolWithTextResponse < ModelContextProtocol::Server::Tool
  with_metadata do
    {
      name: "double",
      description: "Doubles the provided number",
      inputSchema: {
        type: "object",
        properties: {
          number: {
            type: "string"
          }
        },
        required: ["number"]
      }
    }
  end

  def call
    number = params["number"].to_i
    result = number * 2
    respond_with :text, text: "#{number} doubled is #{result}"
  end
end
