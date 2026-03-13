class TestToolWithSecuritySchemes < ModelContextProtocol::Server::Tool
  define do
    name "search"
    description "Search indexed documents"
    input_schema do
      {
        type: "object",
        properties: {
          q: {
            type: "string",
            description: "Search query"
          }
        },
        required: ["q"]
      }
    end
    security_schemes do
      [
        {type: "noauth"},
        {type: "oauth2", scopes: ["search.read"]}
      ]
    end
  end

  def call
    query = arguments[:q]
    client_logger.info("Searching for: #{query}")

    respond_with content: text_content(text: "Results for '#{query}'")
  end
end
