class TestToolWithImageResponseDefaultMimeType < ModelContextProtocol::Server::Tool
  with_metadata do
    {
      name: "custom-chart-generator",
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
    chart_data = "base64encodeddata"
    respond_with :image, data: chart_data
  end
end
