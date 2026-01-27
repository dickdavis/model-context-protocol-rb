require "spec_helper"
require "model_context_protocol/rspec"

RSpec.describe ModelContextProtocol::RSpec::Matchers::HaveResourceMimeType do
  include ModelContextProtocol::RSpec::Matchers
  include McpHelpers

  describe "#matches?" do
    context "with a valid text resource response" do
      it "matches correct mime type" do
        response = call_mcp_resource(TestResource)
        expect(response).to have_resource_mime_type("text/plain")
      end
    end

    context "with a valid binary resource response" do
      it "matches correct mime type" do
        response = call_mcp_resource(TestBinaryResource)
        expect(response).to have_resource_mime_type("image/png")
      end
    end

    context "with annotated resource" do
      it "matches correct mime type" do
        response = call_mcp_resource(TestAnnotatedResource)
        expect(response).to have_resource_mime_type("text/markdown")
      end
    end

    context "with regex match" do
      it "matches mime type with regex" do
        response = call_mcp_resource(TestBinaryResource)
        expect(response).to have_resource_mime_type(/^image\//)
      end

      it "matches text mime type with regex" do
        response = call_mcp_resource(TestResource)
        expect(response).to have_resource_mime_type(/^text\//)
      end
    end

    context "with a Hash response" do
      it "matches when mime type is correct" do
        response = {contents: [{uri: "file:///test.json", mimeType: "application/json", text: "{}"}]}
        expect(response).to have_resource_mime_type("application/json")
      end

      it "matches with string keys" do
        response = {"contents" => [{"uri" => "file:///test.txt", "mimeType" => "text/plain", "text" => "Hello"}]}
        expect(response).to have_resource_mime_type("text/plain")
      end
    end

    context "with non-matching responses" do
      it "fails when mime type does not match" do
        response = call_mcp_resource(TestResource)
        expect(response).not_to have_resource_mime_type("application/json")
      end

      it "fails when regex does not match" do
        response = call_mcp_resource(TestResource)
        expect(response).not_to have_resource_mime_type(/^image\//)
      end
    end

    context "with invalid responses" do
      it "fails for nil response" do
        expect(nil).not_to have_resource_mime_type("text/plain")
      end

      it "fails for response without contents" do
        response = {uri: "file:///test.txt"}
        expect(response).not_to have_resource_mime_type("text/plain")
      end
    end
  end

  describe "#failure_message" do
    it "provides helpful message when mime type does not match" do
      response = {contents: [{uri: "file:///test.txt", mimeType: "text/plain", text: "Hello"}]}
      matcher = have_resource_mime_type("application/json")
      matcher.matches?(response)

      expect(matcher.failure_message).to include("no content with mime type matching")
      expect(matcher.failure_message).to include("text/plain")
    end
  end

  describe "#description" do
    it "returns a description with mime type" do
      matcher = have_resource_mime_type("text/plain")
      expect(matcher.description).to eq('have resource mime type matching "text/plain"')
    end

    it "returns a description with regex" do
      matcher = have_resource_mime_type(/^image\//)
      expect(matcher.description).to eq("have resource mime type matching /^image\\//")
    end
  end
end
