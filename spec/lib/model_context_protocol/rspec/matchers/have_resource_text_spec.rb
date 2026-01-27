require "spec_helper"
require "model_context_protocol/rspec"

RSpec.describe ModelContextProtocol::RSpec::Matchers::HaveResourceText do
  include ModelContextProtocol::RSpec::Matchers
  include McpHelpers

  describe "#matches?" do
    context "with a valid text resource response" do
      it "matches when text is present (substring match)" do
        response = call_mcp_resource(TestResource)
        expect(response).to have_resource_text("eat all my wife's leftovers")
      end

      it "matches with regex" do
        response = call_mcp_resource(TestResource)
        expect(response).to have_resource_text(/leftovers/)
      end
    end

    context "with annotated resource" do
      it "matches text in annotated resource" do
        response = call_mcp_resource(TestAnnotatedResource)
        expect(response).to have_resource_text("Annotated Document")
      end
    end

    context "with a Hash response" do
      it "matches when text is present" do
        response = {contents: [{uri: "file:///test.txt", mimeType: "text/plain", text: "Hello, World!"}]}
        expect(response).to have_resource_text("Hello")
      end

      it "matches with string keys" do
        response = {"contents" => [{"uri" => "file:///test.txt", "mimeType" => "text/plain", "text" => "Hello, World!"}]}
        expect(response).to have_resource_text("Hello")
      end
    end

    context "with non-matching responses" do
      it "fails when text does not match" do
        response = call_mcp_resource(TestResource)
        expect(response).not_to have_resource_text("nonexistent text")
      end

      it "fails when regex does not match" do
        response = call_mcp_resource(TestResource)
        expect(response).not_to have_resource_text(/xyz123/)
      end

      it "fails when resource has blob instead of text" do
        response = call_mcp_resource(TestBinaryResource)
        expect(response).not_to have_resource_text("any text")
      end
    end

    context "with invalid responses" do
      it "fails for nil response" do
        expect(nil).not_to have_resource_text("Hello")
      end

      it "fails for response without contents" do
        response = {uri: "file:///test.txt"}
        expect(response).not_to have_resource_text("Hello")
      end
    end
  end

  describe "#failure_message" do
    it "provides helpful message when no text content found" do
      response = {contents: [{uri: "file:///test.png", mimeType: "image/png", blob: "base64"}]}
      matcher = have_resource_text("Hello")
      matcher.matches?(response)

      expect(matcher.failure_message).to include("no text content found")
    end

    it "provides helpful message when text does not match" do
      response = {contents: [{uri: "file:///test.txt", mimeType: "text/plain", text: "Goodbye"}]}
      matcher = have_resource_text("Hello")
      matcher.matches?(response)

      expect(matcher.failure_message).to include("no text content matched")
      expect(matcher.failure_message).to include("Goodbye")
    end
  end

  describe "#description" do
    it "returns a description with expected text" do
      matcher = have_resource_text("Hello")
      expect(matcher.description).to eq('have resource text matching "Hello"')
    end

    it "returns a description with regex" do
      matcher = have_resource_text(/\d+/)
      expect(matcher.description).to eq("have resource text matching /\\d+/")
    end
  end
end
