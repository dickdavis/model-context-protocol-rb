require "spec_helper"
require "model_context_protocol/rspec"

RSpec.describe ModelContextProtocol::RSpec::Matchers::HaveResourceLinkContent do
  include ModelContextProtocol::RSpec::Matchers
  include McpHelpers

  describe "#matches?" do
    context "with a valid resource link content response" do
      it "matches when resource link is present" do
        response = call_mcp_tool(TestToolWithResourceLinkResponse, {name: "test-doc"})
        expect(response).to have_resource_link_content
      end

      it "matches with uri constraint" do
        response = call_mcp_tool(TestToolWithResourceLinkResponse, {name: "test-doc"})
        expect(response).to have_resource_link_content(uri: "file:///docs/test-doc.md")
      end

      it "matches with name constraint" do
        response = call_mcp_tool(TestToolWithResourceLinkResponse, {name: "test-doc"})
        expect(response).to have_resource_link_content(name: "test-doc")
      end

      it "matches with both uri and name constraints" do
        response = call_mcp_tool(TestToolWithResourceLinkResponse, {name: "test-doc"})
        expect(response).to have_resource_link_content(uri: "file:///docs/test-doc.md", name: "test-doc")
      end
    end

    context "with a Hash response" do
      it "matches when resource link is present" do
        response = {
          content: [{
            type: "resource_link",
            uri: "file:///test.txt",
            name: "test"
          }],
          isError: false
        }
        expect(response).to have_resource_link_content
      end

      it "matches with string keys" do
        response = {
          "content" => [{
            "type" => "resource_link",
            "uri" => "file:///test.txt",
            "name" => "test"
          }],
          "isError" => false
        }
        expect(response).to have_resource_link_content
      end
    end

    context "with non-matching responses" do
      it "fails when no resource link content present" do
        response = {content: [{type: "text", text: "Hello"}], isError: false}
        expect(response).not_to have_resource_link_content
      end

      it "fails when uri does not match" do
        response = {
          content: [{type: "resource_link", uri: "file:///other.txt", name: "other"}],
          isError: false
        }
        expect(response).not_to have_resource_link_content(uri: "file:///test.txt")
      end

      it "fails when name does not match" do
        response = {
          content: [{type: "resource_link", uri: "file:///test.txt", name: "actual"}],
          isError: false
        }
        expect(response).not_to have_resource_link_content(name: "expected")
      end
    end

    context "with invalid responses" do
      it "fails for nil response" do
        expect(nil).not_to have_resource_link_content
      end

      it "fails for response without content" do
        response = {isError: false}
        expect(response).not_to have_resource_link_content
      end
    end
  end

  describe "#failure_message" do
    it "provides helpful message when no resource link content found" do
      response = {content: [{type: "text", text: "Hello"}], isError: false}
      matcher = have_resource_link_content
      matcher.matches?(response)

      expect(matcher.failure_message).to include("no resource link content found")
    end

    it "provides helpful message when uri does not match" do
      response = {
        content: [{type: "resource_link", uri: "file:///actual.txt", name: "test"}],
        isError: false
      }
      matcher = have_resource_link_content(uri: "file:///expected.txt")
      matcher.matches?(response)

      expect(matcher.failure_message).to include("no resource link with uri 'file:///expected.txt'")
      expect(matcher.failure_message).to include("file:///actual.txt")
    end

    it "provides helpful message when name does not match" do
      response = {
        content: [{type: "resource_link", uri: "file:///test.txt", name: "actual"}],
        isError: false
      }
      matcher = have_resource_link_content(name: "expected")
      matcher.matches?(response)

      expect(matcher.failure_message).to include("no resource link with name 'expected'")
      expect(matcher.failure_message).to include("actual")
    end
  end

  describe "#description" do
    it "returns a description without constraints" do
      matcher = have_resource_link_content
      expect(matcher.description).to eq("have resource link content")
    end

    it "returns a description with uri constraint" do
      matcher = have_resource_link_content(uri: "file:///test.txt")
      expect(matcher.description).to eq("have resource link content with uri: 'file:///test.txt'")
    end

    it "returns a description with name constraint" do
      matcher = have_resource_link_content(name: "my-resource")
      expect(matcher.description).to eq("have resource link content with name: 'my-resource'")
    end

    it "returns a description with both constraints" do
      matcher = have_resource_link_content(uri: "file:///test.txt", name: "my-resource")
      expect(matcher.description).to include("uri: 'file:///test.txt'")
      expect(matcher.description).to include("name: 'my-resource'")
    end
  end
end
