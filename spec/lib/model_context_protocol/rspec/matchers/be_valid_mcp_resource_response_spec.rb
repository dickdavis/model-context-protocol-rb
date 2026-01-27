require "spec_helper"
require "model_context_protocol/rspec"

RSpec.describe ModelContextProtocol::RSpec::Matchers::BeValidMcpResourceResponse do
  include ModelContextProtocol::RSpec::Matchers
  include McpHelpers

  describe "#matches?" do
    context "with a valid text resource response" do
      it "matches a resource response with text content" do
        response = call_mcp_resource(TestResource)
        expect(response).to be_valid_mcp_resource_response
      end
    end

    context "with a valid binary resource response" do
      it "matches a resource response with blob content" do
        response = call_mcp_resource(TestBinaryResource)
        expect(response).to be_valid_mcp_resource_response
      end
    end

    context "with a valid annotated resource response" do
      it "matches a resource response with annotations" do
        response = call_mcp_resource(TestAnnotatedResource)
        expect(response).to be_valid_mcp_resource_response
      end
    end

    context "with a Hash response" do
      it "matches a valid Hash response with text" do
        response = {contents: [{uri: "file:///test.txt", mimeType: "text/plain", text: "Hello"}]}
        expect(response).to be_valid_mcp_resource_response
      end

      it "matches a valid Hash response with blob" do
        response = {contents: [{uri: "file:///test.png", mimeType: "image/png", blob: "base64data"}]}
        expect(response).to be_valid_mcp_resource_response
      end

      it "matches with string keys" do
        response = {"contents" => [{"uri" => "file:///test.txt", "mimeType" => "text/plain", "text" => "Hello"}]}
        expect(response).to be_valid_mcp_resource_response
      end
    end

    context "with invalid responses" do
      it "fails for nil response" do
        expect(nil).not_to be_valid_mcp_resource_response
      end

      it "fails for response without serialized method or Hash" do
        expect("invalid").not_to be_valid_mcp_resource_response
      end

      it "fails for response without contents" do
        response = {uri: "file:///test.txt"}
        expect(response).not_to be_valid_mcp_resource_response
      end

      it "fails for response with empty contents array" do
        response = {contents: []}
        expect(response).not_to be_valid_mcp_resource_response
      end

      it "fails for content without uri" do
        response = {contents: [{mimeType: "text/plain", text: "Hello"}]}
        expect(response).not_to be_valid_mcp_resource_response
      end

      it "fails for content without mimeType" do
        response = {contents: [{uri: "file:///test.txt", text: "Hello"}]}
        expect(response).not_to be_valid_mcp_resource_response
      end

      it "fails for content without text or blob" do
        response = {contents: [{uri: "file:///test.txt", mimeType: "text/plain"}]}
        expect(response).not_to be_valid_mcp_resource_response
      end
    end
  end

  describe "#failure_message" do
    it "provides helpful message when contents is missing" do
      response = {uri: "file:///test.txt"}
      matcher = be_valid_mcp_resource_response
      matcher.matches?(response)

      expect(matcher.failure_message).to include("must have :contents key")
    end

    it "provides helpful message when uri is missing" do
      response = {contents: [{mimeType: "text/plain", text: "Hello"}]}
      matcher = be_valid_mcp_resource_response
      matcher.matches?(response)

      expect(matcher.failure_message).to include("must have a :uri key")
    end

    it "provides helpful message when text or blob is missing" do
      response = {contents: [{uri: "file:///test.txt", mimeType: "text/plain"}]}
      matcher = be_valid_mcp_resource_response
      matcher.matches?(response)

      expect(matcher.failure_message).to include("must have either :text or :blob key")
    end
  end

  describe "#description" do
    it "returns a description" do
      matcher = be_valid_mcp_resource_response
      expect(matcher.description).to eq("be a valid MCP resource response")
    end
  end
end
