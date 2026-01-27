# frozen_string_literal: true

module McpHelpers
  # Creates a null logger for testing purposes
  def null_logger
    @null_logger ||= Logger.new(File::NULL)
  end

  # Calls an MCP tool class with the given arguments and context.
  #
  # @param tool_class [Class] The tool class to call (must inherit from ModelContextProtocol::Server::Tool)
  # @param arguments [Hash] Arguments to pass to the tool
  # @param context [Hash] Optional context to pass to the tool
  # @return [Object] The response from the tool
  #
  # @example
  #   response = call_mcp_tool(MyTool, { number: "5" })
  #   expect(response).to be_valid_mcp_tool_response
  #
  def call_mcp_tool(tool_class, arguments = {}, context = {})
    tool_class.call(arguments, null_logger, null_logger, context)
  end

  # Calls an MCP prompt class with the given arguments and context.
  #
  # @param prompt_class [Class] The prompt class to call (must inherit from ModelContextProtocol::Server::Prompt)
  # @param arguments [Hash] Arguments to pass to the prompt
  # @param context [Hash] Optional context to pass to the prompt
  # @return [Object] The response from the prompt
  #
  # @example
  #   response = call_mcp_prompt(MyPrompt, { tone: "friendly" })
  #   expect(response).to be_valid_mcp_prompt_response
  #
  def call_mcp_prompt(prompt_class, arguments = {}, context = {})
    prompt_class.call(arguments, null_logger, null_logger, context)
  end

  # Calls an MCP resource class with the given context.
  #
  # @param resource_class [Class] The resource class to call (must inherit from ModelContextProtocol::Server::Resource)
  # @param context [Hash] Optional context to pass to the resource
  # @return [Object] The response from the resource
  #
  # @example
  #   response = call_mcp_resource(MyResource)
  #   expect(response).to be_valid_mcp_resource_response
  #
  def call_mcp_resource(resource_class, context = {})
    resource_class.call(null_logger, null_logger, context)
  end
end

RSpec.configure do |config|
  # Include helpers for specs with type: :mcp
  config.include McpHelpers, type: :mcp

  # Include helpers for specs in the spec/mcp/ directory
  config.include McpHelpers, file_path: %r{spec/mcp/}
end
