class TestToolWithStructuredContentResponse < ModelContextProtocol::Server::Tool
  define do
    # The name of the tool for programmatic use
    name "get_weather_data"
    # The human-readable tool name for display in UI
    title "Weather Data Retriever"
    # A short description of what the tool does
    description "Get current weather data for a location"
    # The JSON schema for validating tool inputs
    input_schema do
      {
        type: "object",
        properties: {
          location: {
            type: "string",
            description: "City name or zip code"
          }
        },
        required: ["location"]
      }
    end
    # The JSON schema for validating structured content
    output_schema do
      {
        type: "object",
        properties: {
          temperature: {
            type: "number",
            description: "Temperature in celsius"
          },
          conditions: {
            type: "string",
            description: "Weather conditions description"
          },
          humidity: {
            type: "number",
            description: "Humidity percentage"
          }
        },
        required: ["temperature", "conditions", "humidity"]
      }
    end
  end

  def call
    # Use values provided by the server as context
    user_id = context[:user_id]
    logger.info("Initiating request for user #{user_id}...")

    # Use values provided by clients as tool arguments
    location = arguments[:location]
    logger.info("Getting weather data for #{location}...")

    # Returns a hash that validates against the output schema
    weather_data = get_weather_data(location)

    # Respond with structured content
    respond_with structured_content: weather_data
  end

  private

  # Simulate calling an external API to get weather data for the provided input
  def get_weather_data(location)
    {
      temperature: 22.5,
      conditions: "Partly cloudy",
      humidity: 65
    }
  end
end
