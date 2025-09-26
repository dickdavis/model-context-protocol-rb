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
    client_logger.info("Silly user doesn't know how to double a number")
    number = arguments[:number].to_i
    calculation = number * 2

    user_id = context[:user_id]
    salutation = user_id ? "User #{user_id}, " : ""
    text_content = text_content(text: salutation << "#{number} doubled is #{calculation}")

    respond_with content: text_content
  end
end
