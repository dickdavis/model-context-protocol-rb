class TestToolWithTextResponse < ModelContextProtocol::Server::Tool
  with_metadata do
    name "double"
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
    user_id = context[:user_id]
    number = arguments[:number].to_i
    logger.info("Silly user doesn't know how to double a number")
    calculation = number * 2
    salutation = user_id ? "User #{user_id}, " : ""
    respond_with :text, text: salutation << "#{number} doubled is #{calculation}"
  end
end
