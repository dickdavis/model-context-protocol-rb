require "spec_helper"
require "model_context_protocol/rspec"

RSpec.describe ModelContextProtocol::RSpec::Matchers::HaveMessageWithRole do
  include ModelContextProtocol::RSpec::Matchers
  include McpHelpers

  describe "#matches?" do
    context "with a valid prompt response" do
      it "matches when message with role exists" do
        response = call_mcp_prompt(TestPrompt, {undesirable_activity: "clean the garage"})
        expect(response).to have_message_with_role("user")
      end

      it "matches assistant role" do
        response = call_mcp_prompt(TestPrompt, {undesirable_activity: "clean the garage"})
        expect(response).to have_message_with_role("assistant")
      end

      it "matches with symbol role" do
        response = call_mcp_prompt(TestPrompt, {undesirable_activity: "clean the garage"})
        expect(response).to have_message_with_role(:user)
      end
    end

    context "with content constraint" do
      it "matches when content contains expected text" do
        response = call_mcp_prompt(TestPrompt, {undesirable_activity: "clean the garage"})
        expect(response).to have_message_with_role("user").containing("clean the garage")
      end

      it "matches with regex content" do
        response = call_mcp_prompt(TestPrompt, {undesirable_activity: "clean the garage"})
        expect(response).to have_message_with_role("user").containing(/generate.*excuses/i)
      end

      it "matches assistant content" do
        response = call_mcp_prompt(TestPrompt, {undesirable_activity: "clean the garage"})
        expect(response).to have_message_with_role("assistant").containing("How can I help")
      end
    end

    context "with a Hash response" do
      it "matches when message with role exists" do
        response = {
          description: "Test",
          messages: [{role: "user", content: {type: "text", text: "Hello"}}]
        }
        expect(response).to have_message_with_role("user")
      end

      it "matches content in array format" do
        response = {
          description: "Test",
          messages: [{role: "user", content: [{type: "text", text: "Hello World"}]}]
        }
        expect(response).to have_message_with_role("user").containing("Hello")
      end
    end

    context "with non-matching responses" do
      it "fails when role is not present" do
        response = {
          description: "Test",
          messages: [{role: "user", content: {type: "text", text: "Hello"}}]
        }
        expect(response).not_to have_message_with_role("assistant")
      end

      it "fails when content does not match" do
        response = call_mcp_prompt(TestPrompt, {undesirable_activity: "clean the garage"})
        expect(response).not_to have_message_with_role("user").containing("nonexistent text")
      end

      it "fails when regex does not match" do
        response = call_mcp_prompt(TestPrompt, {undesirable_activity: "clean the garage"})
        expect(response).not_to have_message_with_role("user").containing(/xyz123/)
      end
    end

    context "with invalid responses" do
      it "fails for nil response" do
        expect(nil).not_to have_message_with_role("user")
      end

      it "fails for response without messages" do
        response = {description: "Test"}
        expect(response).not_to have_message_with_role("user")
      end
    end
  end

  describe "#failure_message" do
    it "provides helpful message when role is not found" do
      response = {
        description: "Test",
        messages: [{role: "user", content: {type: "text", text: "Hello"}}]
      }
      matcher = have_message_with_role("assistant")
      matcher.matches?(response)

      expect(matcher.failure_message).to include("no message with role 'assistant'")
      expect(matcher.failure_message).to include("user")
    end

    it "provides helpful message when content does not match" do
      response = {
        description: "Test",
        messages: [{role: "user", content: {type: "text", text: "Hello"}}]
      }
      matcher = have_message_with_role("user").containing("Goodbye")
      matcher.matches?(response)

      expect(matcher.failure_message).to include("no 'user' message contains content matching")
    end
  end

  describe "#description" do
    it "returns a description without content constraint" do
      matcher = have_message_with_role("user")
      expect(matcher.description).to eq("have message with role 'user'")
    end

    it "returns a description with content constraint" do
      matcher = have_message_with_role("user").containing("Hello")
      expect(matcher.description).to eq("have message with role 'user' containing \"Hello\"")
    end
  end
end
