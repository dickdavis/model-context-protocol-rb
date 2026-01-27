require "spec_helper"
require "model_context_protocol/rspec"

RSpec.describe ModelContextProtocol::RSpec::Matchers::BeValidMcpPromptResponse do
  include ModelContextProtocol::RSpec::Matchers
  include McpHelpers

  describe "#matches?" do
    context "with a valid prompt response" do
      it "matches a prompt response with messages" do
        response = call_mcp_prompt(TestPrompt, {undesirable_activity: "clean the garage"})
        expect(response).to be_valid_mcp_prompt_response
      end

      it "matches a prompt response with optional tone" do
        response = call_mcp_prompt(TestPrompt, {undesirable_activity: "do laundry", tone: "whiny"})
        expect(response).to be_valid_mcp_prompt_response
      end
    end

    context "with a Hash response" do
      it "matches a valid Hash response" do
        response = {
          description: "A test prompt",
          messages: [
            {role: "user", content: {type: "text", text: "Hello"}}
          ]
        }
        expect(response).to be_valid_mcp_prompt_response
      end

      it "matches with string keys" do
        response = {
          "description" => "A test prompt",
          "messages" => [
            {"role" => "user", "content" => {"type" => "text", "text" => "Hello"}}
          ]
        }
        expect(response).to be_valid_mcp_prompt_response
      end

      it "matches with user and assistant messages" do
        response = {
          description: "A test prompt",
          messages: [
            {role: "user", content: {type: "text", text: "Hello"}},
            {role: "assistant", content: {type: "text", text: "Hi there"}}
          ]
        }
        expect(response).to be_valid_mcp_prompt_response
      end
    end

    context "with invalid responses" do
      it "fails for nil response" do
        expect(nil).not_to be_valid_mcp_prompt_response
      end

      it "fails for response without serialized method or Hash" do
        expect("invalid").not_to be_valid_mcp_prompt_response
      end

      it "fails for response without messages" do
        response = {description: "A prompt"}
        expect(response).not_to be_valid_mcp_prompt_response
      end

      it "fails for response without description" do
        response = {messages: [{role: "user", content: {type: "text", text: "Hi"}}]}
        expect(response).not_to be_valid_mcp_prompt_response
      end

      it "fails for response with empty messages array" do
        response = {description: "A prompt", messages: []}
        expect(response).not_to be_valid_mcp_prompt_response
      end

      it "fails for response with invalid role" do
        response = {description: "A prompt", messages: [{role: "system", content: {}}]}
        expect(response).not_to be_valid_mcp_prompt_response
      end

      it "fails for message without role" do
        response = {description: "A prompt", messages: [{content: {type: "text", text: "Hi"}}]}
        expect(response).not_to be_valid_mcp_prompt_response
      end

      it "fails for message without content" do
        response = {description: "A prompt", messages: [{role: "user"}]}
        expect(response).not_to be_valid_mcp_prompt_response
      end
    end
  end

  describe "#failure_message" do
    it "provides helpful message when messages are missing" do
      response = {description: "A prompt"}
      matcher = be_valid_mcp_prompt_response
      matcher.matches?(response)

      expect(matcher.failure_message).to include("must have :messages key")
    end

    it "provides helpful message when role is invalid" do
      response = {description: "A prompt", messages: [{role: "system", content: {}}]}
      matcher = be_valid_mcp_prompt_response
      matcher.matches?(response)

      expect(matcher.failure_message).to include("invalid role 'system'")
    end
  end

  describe "#description" do
    it "returns a description" do
      matcher = be_valid_mcp_prompt_response
      expect(matcher.description).to eq("be a valid MCP prompt response")
    end
  end
end
