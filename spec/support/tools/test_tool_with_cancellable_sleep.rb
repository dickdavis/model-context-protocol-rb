class TestToolWithCancellableSleep < ModelContextProtocol::Server::Tool
  define do
    name "cancellable_sleep"
    title "Cancellable Sleep Tool"
    description "Sleep for 60 seconds with cancellation support"
    input_schema do
      {
        type: "object",
        properties: {},
        additionalProperties: false
      }
    end
  end

  def call
    client_logger.info("Starting 60 second sleep operation")

    result = cancellable do
      sleep 60
      "Sleep completed successfully"
    end

    respond_with content: text_content(text: result)
  end
end
