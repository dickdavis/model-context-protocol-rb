require "spec_helper"
require "model_context_protocol/rspec"

RSpec.describe ModelContextProtocol::RSpec::Matchers::BeValidMcpToolResponse do
  include ModelContextProtocol::RSpec::Matchers
  include McpHelpers

  describe "#matches?" do
    context "with a valid text content response" do
      it "matches a tool response with text content" do
        response = call_mcp_tool(TestToolWithTextResponse, {number: "5"})
        expect(response).to be_valid_mcp_tool_response
      end
    end

    context "with a valid structured content response" do
      it "matches a tool response with structured content" do
        response = call_mcp_tool(TestToolWithStructuredContentResponse, {location: "NYC"})
        expect(response).to be_valid_mcp_tool_response
      end
    end

    context "with a valid image content response" do
      it "matches a tool response with image content" do
        response = call_mcp_tool(TestToolWithImageResponse, {chart_type: "bar", format: "png"})
        expect(response).to be_valid_mcp_tool_response
      end
    end

    context "with a valid mixed content response" do
      it "matches a tool response with mixed content types" do
        response = call_mcp_tool(TestToolWithMixedContentResponse, {zip: "12345"})
        expect(response).to be_valid_mcp_tool_response
      end
    end

    context "with a valid error response" do
      it "matches a tool error response" do
        response = call_mcp_tool(TestToolWithToolErrorResponse, {api_endpoint: "http://test.com", method: "GET"})
        expect(response).to be_valid_mcp_tool_response
      end
    end

    context "with a valid resource content response" do
      it "matches a tool response with embedded resource content" do
        response = call_mcp_tool(TestToolWithResourceResponse, {name: "test_resource"})
        expect(response).to be_valid_mcp_tool_response
      end
    end

    context "with a Hash response" do
      it "matches a valid Hash response" do
        response = {content: [{type: "text", text: "Hello"}], isError: false}
        expect(response).to be_valid_mcp_tool_response
      end
    end

    context "with invalid responses" do
      it "fails for nil response" do
        expect(nil).not_to be_valid_mcp_tool_response
      end

      it "fails for response without serialized method or Hash" do
        expect("invalid").not_to be_valid_mcp_tool_response
      end

      it "fails for response without content or structuredContent" do
        response = {isError: false}
        expect(response).not_to be_valid_mcp_tool_response
      end

      it "fails for response without isError" do
        response = {content: [{type: "text", text: "Hello"}]}
        expect(response).not_to be_valid_mcp_tool_response
      end

      it "fails for response with empty content array" do
        response = {content: [], isError: false}
        expect(response).not_to be_valid_mcp_tool_response
      end

      it "fails for response with invalid content type" do
        response = {content: [{type: "invalid", data: "test"}], isError: false}
        expect(response).not_to be_valid_mcp_tool_response
      end

      it "fails for response with content item missing type" do
        response = {content: [{text: "Hello"}], isError: false}
        expect(response).not_to be_valid_mcp_tool_response
      end
    end
  end

  describe "#failure_message" do
    it "provides helpful message when response is invalid" do
      matcher = be_valid_mcp_tool_response
      matcher.matches?("invalid")

      expect(matcher.failure_message).to include("must respond to :serialized or be a Hash")
    end

    it "provides helpful message when content is missing" do
      response = {isError: false}
      matcher = be_valid_mcp_tool_response
      matcher.matches?(response)

      expect(matcher.failure_message).to include("must have :content or :structuredContent key")
    end

    it "provides helpful message when content type is invalid" do
      response = {content: [{type: "invalid"}], isError: false}
      matcher = be_valid_mcp_tool_response
      matcher.matches?(response)

      expect(matcher.failure_message).to include("invalid type 'invalid'")
    end
  end

  describe "#description" do
    it "returns a description" do
      matcher = be_valid_mcp_tool_response
      expect(matcher.description).to eq("be a valid MCP tool response")
    end
  end
end
