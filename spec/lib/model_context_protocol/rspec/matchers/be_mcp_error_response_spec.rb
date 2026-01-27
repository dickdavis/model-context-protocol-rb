require "spec_helper"
require "model_context_protocol/rspec"

RSpec.describe ModelContextProtocol::RSpec::Matchers::BeMcpErrorResponse do
  include ModelContextProtocol::RSpec::Matchers
  include McpHelpers

  describe "#matches?" do
    context "with a valid error response" do
      it "matches when isError is true" do
        response = call_mcp_tool(TestToolWithToolErrorResponse, {api_endpoint: "http://test.com", method: "GET"})
        expect(response).to be_mcp_error_response
      end

      it "matches with message substring" do
        response = call_mcp_tool(TestToolWithToolErrorResponse, {api_endpoint: "http://test.com", method: "GET"})
        expect(response).to be_mcp_error_response("Connection timed out")
      end

      it "matches with message regex" do
        response = call_mcp_tool(TestToolWithToolErrorResponse, {api_endpoint: "http://test.com", method: "GET"})
        expect(response).to be_mcp_error_response(/Connection.*out/)
      end

      it "matches with api endpoint in message" do
        response = call_mcp_tool(TestToolWithToolErrorResponse, {api_endpoint: "http://example.com/api", method: "POST"})
        expect(response).to be_mcp_error_response("http://example.com/api")
      end
    end

    context "with a Hash response" do
      it "matches when isError is true" do
        response = {content: [{type: "text", text: "Error occurred"}], isError: true}
        expect(response).to be_mcp_error_response
      end

      it "matches with string keys" do
        response = {"content" => [{"type" => "text", "text" => "Error occurred"}], "isError" => true}
        expect(response).to be_mcp_error_response
      end
    end

    context "with non-matching responses" do
      it "fails when isError is false" do
        response = call_mcp_tool(TestToolWithTextResponse, {number: "5"})
        expect(response).not_to be_mcp_error_response
      end

      it "fails when message does not match" do
        response = call_mcp_tool(TestToolWithToolErrorResponse, {api_endpoint: "http://test.com", method: "GET"})
        expect(response).not_to be_mcp_error_response("Authentication failed")
      end

      it "fails when regex does not match" do
        response = call_mcp_tool(TestToolWithToolErrorResponse, {api_endpoint: "http://test.com", method: "GET"})
        expect(response).not_to be_mcp_error_response(/404 not found/)
      end
    end

    context "with invalid responses" do
      it "fails for nil response" do
        expect(nil).not_to be_mcp_error_response
      end

      it "fails for response without isError" do
        response = {content: [{type: "text", text: "Error"}]}
        expect(response).not_to be_mcp_error_response
      end

      it "fails for response with isError: false" do
        response = {content: [{type: "text", text: "Hello"}], isError: false}
        expect(response).not_to be_mcp_error_response
      end
    end
  end

  describe "#failure_message" do
    it "provides helpful message when isError is not true" do
      response = {content: [{type: "text", text: "Hello"}], isError: false}
      matcher = be_mcp_error_response
      matcher.matches?(response)

      expect(matcher.failure_message).to include("isError is not true")
    end

    it "provides helpful message when message does not match" do
      response = {content: [{type: "text", text: "Actual error message"}], isError: true}
      matcher = be_mcp_error_response("Expected error")
      matcher.matches?(response)

      expect(matcher.failure_message).to include("no error message matched")
      expect(matcher.failure_message).to include("Actual error message")
    end
  end

  describe "#description" do
    it "returns a description without message constraint" do
      matcher = be_mcp_error_response
      expect(matcher.description).to eq("be an MCP error response")
    end

    it "returns a description with string message constraint" do
      matcher = be_mcp_error_response("Error occurred")
      expect(matcher.description).to eq('be an MCP error response with message matching "Error occurred"')
    end

    it "returns a description with regex message constraint" do
      matcher = be_mcp_error_response(/error/i)
      expect(matcher.description).to eq("be an MCP error response with message matching /error/i")
    end
  end
end
