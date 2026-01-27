require "spec_helper"
require "model_context_protocol/rspec"

RSpec.describe ModelContextProtocol::RSpec::Matchers::HaveStructuredContent do
  include ModelContextProtocol::RSpec::Matchers
  include McpHelpers

  describe "#matches?" do
    context "with a valid structured content response" do
      it "matches when expected content is present" do
        response = call_mcp_tool(TestToolWithStructuredContentResponse, {location: "NYC"})
        expect(response).to have_structured_content(temperature: 22.5)
      end

      it "matches when multiple expected keys are present" do
        response = call_mcp_tool(TestToolWithStructuredContentResponse, {location: "NYC"})
        expect(response).to have_structured_content(temperature: 22.5, conditions: "Partly cloudy")
      end

      it "matches when all expected keys are present" do
        response = call_mcp_tool(TestToolWithStructuredContentResponse, {location: "NYC"})
        expect(response).to have_structured_content(temperature: 22.5, conditions: "Partly cloudy", humidity: 65)
      end
    end

    context "with a Hash response" do
      it "matches when expected content is present" do
        response = {structuredContent: {name: "test", value: 42}, content: [{type: "text", text: "{}"}], isError: false}
        expect(response).to have_structured_content(name: "test")
      end

      it "matches with string keys" do
        response = {"structuredContent" => {"name" => "test"}, "content" => [{"type" => "text", "text" => "{}"}], "isError" => false}
        expect(response).to have_structured_content(name: "test")
      end
    end

    context "with non-matching responses" do
      it "fails when structuredContent key is missing" do
        response = {content: [{type: "text", text: "Hello"}], isError: false}
        expect(response).not_to have_structured_content(name: "test")
      end

      it "fails when expected key is missing" do
        response = {structuredContent: {name: "test"}, content: [{type: "text", text: "{}"}], isError: false}
        expect(response).not_to have_structured_content(missing_key: "value")
      end

      it "fails when expected value does not match" do
        response = {structuredContent: {name: "test"}, content: [{type: "text", text: "{}"}], isError: false}
        expect(response).not_to have_structured_content(name: "other")
      end
    end

    context "with invalid responses" do
      it "fails for nil response" do
        expect(nil).not_to have_structured_content(name: "test")
      end

      it "fails for non-Hash response without serialized method" do
        expect("invalid").not_to have_structured_content(name: "test")
      end
    end
  end

  describe "#failure_message" do
    it "provides helpful message when structuredContent is missing" do
      response = {content: [{type: "text", text: "Hello"}], isError: false}
      matcher = have_structured_content(name: "test")
      matcher.matches?(response)

      expect(matcher.failure_message).to include("does not have :structuredContent key")
    end

    it "provides helpful message when expected key is missing" do
      response = {structuredContent: {other: "value"}, content: [{type: "text", text: "{}"}], isError: false}
      matcher = have_structured_content(name: "test")
      matcher.matches?(response)

      expect(matcher.failure_message).to include("missing key :name")
    end

    it "provides helpful message when value does not match" do
      response = {structuredContent: {name: "actual"}, content: [{type: "text", text: "{}"}], isError: false}
      matcher = have_structured_content(name: "expected")
      matcher.matches?(response)

      expect(matcher.failure_message).to include("expected :name to be")
    end
  end

  describe "#description" do
    it "returns a description with expected content" do
      matcher = have_structured_content(temperature: 22.5)
      expect(matcher.description).to include("have structured content matching")
      expect(matcher.description).to include("temperature")
    end
  end
end
