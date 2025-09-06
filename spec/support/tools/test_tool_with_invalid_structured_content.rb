class TestToolWithInvalidStructuredContent < ModelContextProtocol::Server::Tool
  define do
    name "invalid_weather_data"
    description "Returns invalid weather data to test schema validation"
    input_schema do
      {
        type: "object",
        properties: {
          location: {
            type: "string"
          }
        },
        required: ["location"]
      }
    end
    output_schema do
      {
        type: "object",
        properties: {
          temperature: {
            type: "number"
          },
          conditions: {
            type: "string"
          }
        },
        required: ["temperature", "conditions"]
      }
    end
  end

  def call
    # Return invalid data - missing required field and wrong type
    invalid_data = {
      temperature: "not a number", # should be number
      # missing required 'conditions' field
      extra_field: "should not be here"
    }

    respond_with structured_content: invalid_data
  end
end
