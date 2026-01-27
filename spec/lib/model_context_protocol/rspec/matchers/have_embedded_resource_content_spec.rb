require "spec_helper"
require "model_context_protocol/rspec"

RSpec.describe ModelContextProtocol::RSpec::Matchers::HaveEmbeddedResourceContent do
  include ModelContextProtocol::RSpec::Matchers
  include McpHelpers

  describe "#matches?" do
    context "with a valid embedded resource content response" do
      it "matches when embedded resource is present" do
        response = call_mcp_tool(TestToolWithResourceResponse, {name: "test_resource"})
        expect(response).to have_embedded_resource_content
      end

      it "matches with uri constraint" do
        response = call_mcp_tool(TestToolWithResourceResponse, {name: "test_resource"})
        expect(response).to have_embedded_resource_content(uri: "file:///top-secret-plans.txt")
      end

      it "matches with mime_type constraint" do
        response = call_mcp_tool(TestToolWithResourceResponse, {name: "test_resource"})
        expect(response).to have_embedded_resource_content(mime_type: "text/plain")
      end

      it "matches with both uri and mime_type constraints" do
        response = call_mcp_tool(TestToolWithResourceResponse, {name: "test_resource"})
        expect(response).to have_embedded_resource_content(uri: "file:///top-secret-plans.txt", mime_type: "text/plain")
      end
    end

    context "with a binary resource" do
      it "matches binary resource with image mime type" do
        response = call_mcp_tool(TestToolWithResourceResponse, {name: "test_binary_resource"})
        expect(response).to have_embedded_resource_content(mime_type: "image/png")
      end
    end

    context "with a Hash response" do
      it "matches when embedded resource is present" do
        response = {
          content: [{
            type: "resource",
            resource: {
              contents: [{uri: "file:///test.txt", mimeType: "text/plain", text: "Hello"}]
            }
          }],
          isError: false
        }
        expect(response).to have_embedded_resource_content
      end

      it "matches with string keys" do
        response = {
          "content" => [{
            "type" => "resource",
            "resource" => {
              "contents" => [{"uri" => "file:///test.txt", "mimeType" => "text/plain", "text" => "Hello"}]
            }
          }],
          "isError" => false
        }
        expect(response).to have_embedded_resource_content
      end
    end

    context "with non-matching responses" do
      it "fails when no embedded resource content present" do
        response = {content: [{type: "text", text: "Hello"}], isError: false}
        expect(response).not_to have_embedded_resource_content
      end

      it "fails when uri does not match" do
        response = call_mcp_tool(TestToolWithResourceResponse, {name: "test_resource"})
        expect(response).not_to have_embedded_resource_content(uri: "file:///other.txt")
      end

      it "fails when mime_type does not match" do
        response = call_mcp_tool(TestToolWithResourceResponse, {name: "test_resource"})
        expect(response).not_to have_embedded_resource_content(mime_type: "application/json")
      end
    end

    context "with invalid responses" do
      it "fails for nil response" do
        expect(nil).not_to have_embedded_resource_content
      end

      it "fails for response without content" do
        response = {isError: false}
        expect(response).not_to have_embedded_resource_content
      end
    end
  end

  describe "#failure_message" do
    it "provides helpful message when no embedded resource content found" do
      response = {content: [{type: "text", text: "Hello"}], isError: false}
      matcher = have_embedded_resource_content
      matcher.matches?(response)

      expect(matcher.failure_message).to include("no embedded resource content found")
    end

    it "provides helpful message when uri does not match" do
      response = {
        content: [{
          type: "resource",
          resource: {contents: [{uri: "file:///actual.txt", mimeType: "text/plain"}]}
        }],
        isError: false
      }
      matcher = have_embedded_resource_content(uri: "file:///expected.txt")
      matcher.matches?(response)

      expect(matcher.failure_message).to include("no embedded resource with uri 'file:///expected.txt'")
    end
  end

  describe "#description" do
    it "returns a description without constraints" do
      matcher = have_embedded_resource_content
      expect(matcher.description).to eq("have embedded resource content")
    end

    it "returns a description with uri constraint" do
      matcher = have_embedded_resource_content(uri: "file:///test.txt")
      expect(matcher.description).to eq("have embedded resource content with uri: 'file:///test.txt'")
    end

    it "returns a description with mime_type constraint" do
      matcher = have_embedded_resource_content(mime_type: "text/plain")
      expect(matcher.description).to eq("have embedded resource content with mime_type: 'text/plain'")
    end

    it "returns a description with both constraints" do
      matcher = have_embedded_resource_content(uri: "file:///test.txt", mime_type: "text/plain")
      expect(matcher.description).to include("uri: 'file:///test.txt'")
      expect(matcher.description).to include("mime_type: 'text/plain'")
    end
  end
end
