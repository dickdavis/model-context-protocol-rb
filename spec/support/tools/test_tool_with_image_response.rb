class TestToolWithImageResponse < ModelContextProtocol::Server::Tool
  with_metadata do
    {
      name: "custom-chart-generator",
      description: "Generates a chart in various formats",
      inputSchema: {
        type: "object",
        properties: {
          chart_type: {
            type: "string",
            description: "Type of chart (pie, bar, line)"
          },
          format: {
            type: "string",
            description: "Image format (jpg, svg, etc)"
          }
        },
        required: ["chart_type", "format"]
      }
    }
  end

  def call
    # Map format to mime type
    mime_type = case params["format"].downcase
    when "svg"
      "image/svg+xml"
    when "jpg", "jpeg"
      "image/jpeg"
    else
      "image/png"
    end

    # In a real implementation, we would generate an actual chart
    chart_data = "base64encodeddata"
    respond_with :image, data: chart_data, mime_type:
  end
end
