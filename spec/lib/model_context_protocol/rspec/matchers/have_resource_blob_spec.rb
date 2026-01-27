require "spec_helper"
require "model_context_protocol/rspec"

RSpec.describe ModelContextProtocol::RSpec::Matchers::HaveResourceBlob do
  include ModelContextProtocol::RSpec::Matchers
  include McpHelpers

  describe "#matches?" do
    context "with a valid binary resource response" do
      it "matches when blob is present" do
        response = call_mcp_resource(TestBinaryResource)
        expect(response).to have_resource_blob
      end

      it "matches with specific blob content" do
        response = call_mcp_resource(TestBinaryResource)
        expect(response).to have_resource_blob("dGVzdA==")
      end
    end

    context "with a Hash response" do
      it "matches when blob is present" do
        response = {contents: [{uri: "file:///test.png", mimeType: "image/png", blob: "base64data"}]}
        expect(response).to have_resource_blob
      end

      it "matches with specific blob content" do
        response = {contents: [{uri: "file:///test.png", mimeType: "image/png", blob: "specific_base64"}]}
        expect(response).to have_resource_blob("specific_base64")
      end

      it "matches with string keys" do
        response = {"contents" => [{"uri" => "file:///test.png", "mimeType" => "image/png", "blob" => "base64data"}]}
        expect(response).to have_resource_blob
      end
    end

    context "with non-matching responses" do
      it "fails when no blob present" do
        response = call_mcp_resource(TestResource)
        expect(response).not_to have_resource_blob
      end

      it "fails when blob content does not match" do
        response = call_mcp_resource(TestBinaryResource)
        expect(response).not_to have_resource_blob("different_base64")
      end
    end

    context "with invalid responses" do
      it "fails for nil response" do
        expect(nil).not_to have_resource_blob
      end

      it "fails for response without contents" do
        response = {uri: "file:///test.png"}
        expect(response).not_to have_resource_blob
      end
    end
  end

  describe "#failure_message" do
    it "provides helpful message when no blob content found" do
      response = {contents: [{uri: "file:///test.txt", mimeType: "text/plain", text: "Hello"}]}
      matcher = have_resource_blob
      matcher.matches?(response)

      expect(matcher.failure_message).to include("no blob content found")
    end

    it "provides helpful message when blob does not match" do
      response = {contents: [{uri: "file:///test.png", mimeType: "image/png", blob: "actual_blob"}]}
      matcher = have_resource_blob("expected_blob")
      matcher.matches?(response)

      expect(matcher.failure_message).to include("no blob content matched")
      expect(matcher.failure_message).to include("actual_blob")
    end
  end

  describe "#description" do
    it "returns a description without specific blob" do
      matcher = have_resource_blob
      expect(matcher.description).to eq("have resource blob content")
    end

    it "returns a description with specific blob" do
      matcher = have_resource_blob("base64data")
      expect(matcher.description).to eq('have resource blob content matching "base64data"')
    end
  end
end
