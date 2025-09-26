class TestToolWithMixedContentResponse < ModelContextProtocol::Server::Tool
  define do
    name "get_temperature_history"
    description "Gets comprehensive temperature history for a zip code"
    input_schema do
      {
        type: "object",
        properties: {
          zip: {
            type: "string"
          }
        },
        required: ["zip"]
      }
    end
  end

  def call
    client_logger.info("Getting comprehensive temperature history data")

    zip = arguments[:zip]
    temperature_history = retrieve_temperature_history(zip:)
    temperature_history_block = text_content(text: temperature_history.join(", "))

    temperature_chart = generate_weather_history_chart(temperature_history)
    temperature_chart_block = image_content(
      data: temperature_chart[:base64_chart_data],
      mime_type: temperature_chart[:mime_type]
    )

    respond_with content: [temperature_history_block, temperature_chart_block]
  end

  private

  def retrieve_temperature_history(zip:)
    # Simulates a call to an API or DB to retrieve weather history
    [85.2, 87.4, 89.0, 95.3, 96.0]
  end

  def generate_weather_history_chart(history)
    # SImulate a call to generate a chart given the weather history
    {
      base64_chart_data: "dGVzdA==",
      mime_type: "image/png"
    }
  end
end
