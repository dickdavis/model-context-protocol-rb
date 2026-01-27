require "spec_helper"
require "model_context_protocol/rspec"

RSpec.describe ModelContextProtocol::RSpec::Matchers::HaveResourceAnnotations do
  include ModelContextProtocol::RSpec::Matchers
  include McpHelpers

  describe "#matches?" do
    context "with a valid annotated resource response" do
      it "matches when priority annotation is present" do
        response = call_mcp_resource(TestAnnotatedResource)
        expect(response).to have_resource_annotations(priority: 0.9)
      end

      it "matches when audience annotation is present" do
        response = call_mcp_resource(TestAnnotatedResource)
        expect(response).to have_resource_annotations(audience: ["user", "assistant"])
      end

      it "matches with lastModified annotation" do
        response = call_mcp_resource(TestAnnotatedResource)
        expect(response).to have_resource_annotations(lastModified: "2025-01-12T15:00:58Z")
      end

      it "matches with snake_case key conversion to camelCase" do
        response = call_mcp_resource(TestAnnotatedResource)
        expect(response).to have_resource_annotations(last_modified: "2025-01-12T15:00:58Z")
      end

      it "matches multiple annotations" do
        response = call_mcp_resource(TestAnnotatedResource)
        expect(response).to have_resource_annotations(priority: 0.9, audience: ["user", "assistant"])
      end
    end

    context "with a Hash response" do
      it "matches when annotations are present" do
        response = {
          contents: [{
            uri: "file:///test.txt",
            mimeType: "text/plain",
            text: "Hello",
            annotations: {priority: 0.5}
          }]
        }
        expect(response).to have_resource_annotations(priority: 0.5)
      end

      it "matches with string keys" do
        response = {
          "contents" => [{
            "uri" => "file:///test.txt",
            "mimeType" => "text/plain",
            "text" => "Hello",
            "annotations" => {"priority" => 0.5}
          }]
        }
        expect(response).to have_resource_annotations(priority: 0.5)
      end
    end

    context "with non-matching responses" do
      it "fails when no annotations present" do
        response = call_mcp_resource(TestResource)
        expect(response).not_to have_resource_annotations(priority: 0.5)
      end

      it "fails when annotation value does not match" do
        response = call_mcp_resource(TestAnnotatedResource)
        expect(response).not_to have_resource_annotations(priority: 0.5)
      end

      it "fails when annotation key is missing" do
        response = {
          contents: [{
            uri: "file:///test.txt",
            mimeType: "text/plain",
            text: "Hello",
            annotations: {priority: 0.5}
          }]
        }
        expect(response).not_to have_resource_annotations(audience: ["user"])
      end
    end

    context "with invalid responses" do
      it "fails for nil response" do
        expect(nil).not_to have_resource_annotations(priority: 0.5)
      end

      it "fails for response without contents" do
        response = {uri: "file:///test.txt"}
        expect(response).not_to have_resource_annotations(priority: 0.5)
      end
    end
  end

  describe "#failure_message" do
    it "provides helpful message when no annotations found" do
      response = {contents: [{uri: "file:///test.txt", mimeType: "text/plain", text: "Hello"}]}
      matcher = have_resource_annotations(priority: 0.5)
      matcher.matches?(response)

      expect(matcher.failure_message).to include("no content with annotations found")
    end

    it "provides helpful message when annotations do not match" do
      response = {
        contents: [{
          uri: "file:///test.txt",
          mimeType: "text/plain",
          text: "Hello",
          annotations: {priority: 0.3}
        }]
      }
      matcher = have_resource_annotations(priority: 0.5)
      matcher.matches?(response)

      expect(matcher.failure_message).to include("no content with matching annotations found")
    end
  end

  describe "#description" do
    it "returns a description with expected annotations" do
      matcher = have_resource_annotations(priority: 0.5)
      expect(matcher.description).to include("have resource annotations matching")
      expect(matcher.description).to include("priority")
    end
  end
end
