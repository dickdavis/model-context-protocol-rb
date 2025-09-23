class TestToolWithProgressableAndCancellable < ModelContextProtocol::Server::Tool
  define do
    name "test_tool_with_progressable_and_cancellable"
    description "A test tool that demonstrates combined progressable and cancellable functionality"

    input_schema do
      {
        type: "object",
        properties: {
          max_duration: {
            type: "number",
            description: "Expected maximum duration in seconds"
          },
          work_steps: {
            type: "number",
            description: "Number of work steps to perform"
          }
        },
        required: ["max_duration"]
      }
    end
  end

  def call
    max_duration = arguments[:max_duration] || 10
    work_steps = arguments[:work_steps] || 10

    logger.info("Starting progressable call with max_duration=#{max_duration}, work_steps=#{work_steps}")

    context = Thread.current[:mcp_context]
    logger.info("MCP Context: #{context.inspect}")

    result = progressable(max_duration:, message: "Processing #{work_steps} items") do
      cancellable do
        processed_items = []

        work_steps.times do |i|
          logger.info("Processing item #{i + 1} of #{work_steps}")
          sleep(max_duration / work_steps.to_f)
          processed_items << "item_#{i + 1}"
        end

        processed_items
      end
    end

    response = text_content(text: "Successfully processed #{result.length} items: #{result.join(", ")}")

    respond_with content: response
  end
end
