require "spec_helper"
require "model_context_protocol/rspec"

RSpec.describe ModelContextProtocol::RSpec::Matchers::HaveTextContent do
  include ModelContextProtocol::RSpec::Matchers
  include McpHelpers

  describe "#matches?" do
    context "with a valid text content response" do
      it "matches when text is present (substring match)" do
        response = call_mcp_tool(TestToolWithTextResponse, {number: "5"})
        expect(response).to have_text_content("doubled is 10")
      end

      it "matches with regex" do
        response = call_mcp_tool(TestToolWithTextResponse, {number: "5"})
        expect(response).to have_text_content(/doubled is \d+/)
      end

      it "matches with context in response" do
        response = call_mcp_tool(TestToolWithTextResponse, {number: "5"}, {user_id: "123"})
        expect(response).to have_text_content("User 123")
      end
    end

    context "with mixed content response" do
      it "matches text in mixed content" do
        response = call_mcp_tool(TestToolWithMixedContentResponse, {zip: "12345"})
        expect(response).to have_text_content("85.2")
      end
    end

    context "with a Hash response" do
      it "matches when text is present" do
        response = {content: [{type: "text", text: "Hello, World!"}], isError: false}
        expect(response).to have_text_content("Hello")
      end

      it "matches with string keys" do
        response = {"content" => [{"type" => "text", "text" => "Hello, World!"}], "isError" => false}
        expect(response).to have_text_content("Hello")
      end
    end

    context "with non-matching responses" do
      it "fails when text does not match" do
        response = call_mcp_tool(TestToolWithTextResponse, {number: "5"})
        expect(response).not_to have_text_content("tripled")
      end

      it "fails when regex does not match" do
        response = call_mcp_tool(TestToolWithTextResponse, {number: "5"})
        expect(response).not_to have_text_content(/tripled is \d+/)
      end

      it "fails when content has no text type" do
        response = {content: [{type: "image", data: "base64", mimeType: "image/png"}], isError: false}
        expect(response).not_to have_text_content("Hello")
      end
    end

    context "with invalid responses" do
      it "fails for nil response" do
        expect(nil).not_to have_text_content("Hello")
      end

      it "fails for response without content" do
        response = {isError: false}
        expect(response).not_to have_text_content("Hello")
      end
    end
  end

  describe "#failure_message" do
    it "provides helpful message when no text content found" do
      response = {content: [{type: "image", data: "base64", mimeType: "image/png"}], isError: false}
      matcher = have_text_content("Hello")
      matcher.matches?(response)

      expect(matcher.failure_message).to include("no text content found")
    end

    it "provides helpful message when text does not match" do
      response = {content: [{type: "text", text: "Goodbye"}], isError: false}
      matcher = have_text_content("Hello")
      matcher.matches?(response)

      expect(matcher.failure_message).to include("no text content matched")
      expect(matcher.failure_message).to include("Goodbye")
    end
  end

  describe "#description" do
    it "returns a description with expected text" do
      matcher = have_text_content("Hello")
      expect(matcher.description).to eq('have text content matching "Hello"')
    end

    it "returns a description with regex" do
      matcher = have_text_content(/\d+/)
      expect(matcher.description).to eq("have text content matching /\\d+/")
    end
  end
end
