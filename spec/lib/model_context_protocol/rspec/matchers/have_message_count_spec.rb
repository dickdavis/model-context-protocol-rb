require "spec_helper"
require "model_context_protocol/rspec"

RSpec.describe ModelContextProtocol::RSpec::Matchers::HaveMessageCount do
  include ModelContextProtocol::RSpec::Matchers
  include McpHelpers

  describe "#matches?" do
    context "with a valid prompt response" do
      it "matches correct message count" do
        response = call_mcp_prompt(TestPrompt, {undesirable_activity: "clean the garage"})
        expect(response).to have_message_count(3)
      end
    end

    context "with a Hash response" do
      it "matches when count is correct" do
        response = {
          description: "Test",
          messages: [
            {role: "user", content: {type: "text", text: "Hello"}},
            {role: "assistant", content: {type: "text", text: "Hi"}}
          ]
        }
        expect(response).to have_message_count(2)
      end

      it "matches single message" do
        response = {
          description: "Test",
          messages: [{role: "user", content: {type: "text", text: "Hello"}}]
        }
        expect(response).to have_message_count(1)
      end
    end

    context "with non-matching responses" do
      it "fails when count is incorrect" do
        response = call_mcp_prompt(TestPrompt, {undesirable_activity: "clean the garage"})
        expect(response).not_to have_message_count(5)
      end

      it "fails when count is zero but has messages" do
        response = {
          description: "Test",
          messages: [{role: "user", content: {type: "text", text: "Hello"}}]
        }
        expect(response).not_to have_message_count(0)
      end
    end

    context "with invalid responses" do
      it "fails for nil response" do
        expect(nil).not_to have_message_count(1)
      end

      it "fails for response without messages" do
        response = {description: "Test"}
        expect(response).not_to have_message_count(1)
      end
    end
  end

  describe "#failure_message" do
    it "provides helpful message when count is incorrect" do
      response = {
        description: "Test",
        messages: [{role: "user", content: {type: "text", text: "Hello"}}]
      }
      matcher = have_message_count(3)
      matcher.matches?(response)

      expect(matcher.failure_message).to include("expected 3 message(s), got 1")
    end
  end

  describe "#description" do
    it "returns a description with count" do
      matcher = have_message_count(3)
      expect(matcher.description).to eq("have 3 message(s)")
    end

    it "returns a description with singular count" do
      matcher = have_message_count(1)
      expect(matcher.description).to eq("have 1 message(s)")
    end
  end
end
