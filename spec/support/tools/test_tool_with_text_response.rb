class TestToolWithTextResponse < ModelContextProtocol::Server::Tool
  define do
    name "double"
    title "Number Doubler"
    description "Doubles the provided number"
    input_schema do
      {
        type: "object",
        properties: {
          number: {
            type: "string"
          }
        },
        required: ["number"]
      }
    end
  end

  def call
    # Log to client (via MCP protocol) for user visibility
    client_logger.info("Processing number doubling request")

    # Log to server (stderr/file) for debugging - not sent to client
    server_logger.debug("Tool called with arguments: #{arguments}")

    number = arguments[:number].to_i
    server_logger.debug("Parsed number: #{number}")

    calculation = number * 2
    server_logger.info("Calculation completed: #{number} * 2 = #{calculation}")

    user_id = context[:user_id]
    salutation = user_id ? "User #{user_id}, " : ""
    text_content = text_content(text: salutation << "#{number} doubled is #{calculation}")

    server_logger.debug("Responding with content: #{text_content}")
    respond_with content: text_content
  end
end
