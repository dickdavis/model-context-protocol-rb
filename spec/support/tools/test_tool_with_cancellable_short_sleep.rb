class TestToolWithCancellableShortSleep < ModelContextProtocol::Server::Tool
  define do
    name "cancellable_short_sleep"
    title "Cancellable Short Sleep Tool"
    description "Sleep for 2 seconds with cancellation support"
    input_schema do
      {
        type: "object",
        properties: {},
        additionalProperties: false
      }
    end
  end

  def call
    client_logger.info("Starting 2 second sleep operation")

    result = cancellable do
      sleep 2
      "Sleep completed successfully"
    end

    respond_with content: text_content(text: result)
  end
end
