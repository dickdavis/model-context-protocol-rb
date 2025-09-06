class TestToolWithToolErrorResponse < ModelContextProtocol::Server::Tool
  define do
    name "api-caller"
    description "Makes calls to external APIs"
    input_schema do
      {
        type: "object",
        properties: {
          api_endpoint: {
            type: "string",
            description: "API endpoint URL"
          },
          method: {
            type: "string",
            description: "HTTP method (GET, POST, etc)"
          }
        },
        required: ["api_endpoint", "method"]
      }
    end
  end

  def call
    # Simulate an API call failure
    respond_with error: "Failed to call API at #{arguments[:api_endpoint]}: Connection timed out"
  end
end
