require "spec_helper"
require "model_context_protocol/rspec"

RSpec.describe ModelContextProtocol::RSpec::Helpers do
  include ModelContextProtocol::RSpec::Helpers

  describe "#null_logger" do
    it "returns a Logger instance" do
      expect(null_logger).to be_a(Logger)
    end

    it "returns the same instance on subsequent calls" do
      expect(null_logger).to be(null_logger)
    end
  end

  describe "#call_mcp_tool" do
    it "calls the tool and returns a response" do
      response = call_mcp_tool(TestToolWithTextResponse, {number: "5"})
      expect(response.serialized).to include(:content, :isError)
    end

    it "passes context to the tool" do
      response = call_mcp_tool(TestToolWithTextResponse, {number: "5"}, {user_id: "42"})
      expect(response.serialized[:content].first[:text]).to include("User 42")
    end
  end

  describe "#call_mcp_prompt" do
    it "calls the prompt and returns a response" do
      response = call_mcp_prompt(TestPrompt, {undesirable_activity: "clean the garage"})
      expect(response.serialized).to include(:messages)
    end

    it "passes context to the prompt" do
      response = call_mcp_prompt(TestPrompt, {undesirable_activity: "clean the garage"}, {user_id: "42"})
      expect(response.serialized[:messages]).to be_an(Array)
    end
  end

  describe "#call_mcp_resource" do
    it "calls the resource and returns a response" do
      response = call_mcp_resource(TestResource)
      expect(response.serialized).to include(:contents)
    end

    it "passes context to the resource" do
      response = call_mcp_resource(TestResource, {user_id: "42"})
      expect(response.serialized[:contents]).to be_an(Array)
    end
  end
end
