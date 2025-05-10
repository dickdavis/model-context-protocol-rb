require "spec_helper"

RSpec.describe ModelContextProtocol::Server::ResourceTemplate do
  describe ".call" do
    it "returns the response from the instance's call method" do
      response = TestResourceTemplate.call("resource:///test-resource")
      aggregate_failures do
        expect(response.text).to eq("Here's the resource name you requested: test-resource")
        expect(response.serialized).to eq(
          contents: [
            {
              mimeType: "text/plain",
              text: "Here's the resource name you requested: test-resource",
              uri: "resource:///test-resource"
            }
          ]
        )
      end
    end
  end

  describe "responses" do
    describe "text response" do
      it "formats text responses correctly" do
        response = TestResourceTemplate.call("resource:///test-resource")
        expect(response.serialized).to eq(
          contents: [
            {
              mimeType: "text/plain",
              text: "Here's the resource name you requested: test-resource",
              uri: "resource:///test-resource"
            }
          ]
        )
      end
    end

    describe "binary response" do
      it "formats binary responses correctly" do
        response = TestBinaryResourceTemplate.call("resource://project-logo")

        expect(response.serialized).to eq(
          contents: [
            {
              blob: "dGVzdA==",
              mimeType: "image/jpeg",
              uri: "resource://project-logo"
            }
          ]
        )
      end
    end
  end

  describe "with_metadata" do
    it "sets the class metadata" do
      aggregate_failures do
        expect(TestResourceTemplate.name).to eq("Test Resource Template")
        expect(TestResourceTemplate.description).to eq("A test resource template")
        expect(TestResourceTemplate.mime_type).to eq("text/plain")
        expect(TestResourceTemplate.uri_template).to eq("resource:///{name}")
        expect(TestResourceTemplate.completions).to eq({"name" => TestResourceTemplateCompletion})
      end
    end
  end

  describe "metadata" do
    it "returns class metadata" do
      expect(TestResourceTemplate.metadata).to eq(
        name: "Test Resource Template",
        description: "A test resource template",
        mimeType: "text/plain",
        uriTemplate: "resource:///{name}",
        completions: {"name" => TestResourceTemplateCompletion}
      )
    end
  end
end
