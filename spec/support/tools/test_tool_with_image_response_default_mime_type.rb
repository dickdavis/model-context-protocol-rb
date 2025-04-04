class TestToolWithImageResponseDefaultMimeType < ModelContextProtocol::Server::Tool
  with_metadata do
    {
      name: "other-custom-chart-generator",
      description: "Generates a chart",
      inputSchema: {
        type: "object",
        properties: {
          chart_type: {
            type: "string",
            description: "Type of chart (pie, bar, line)"
          }
        },
        required: ["chart_type"]
      }
    }
  end

  def call
    # In a real implementation, we would generate an actual chart
    # This is a small valid base64 encoded string (represents "test")
    chart_data = "dGVzdA=="
    respond_with :image, data: chart_data
  end
end
