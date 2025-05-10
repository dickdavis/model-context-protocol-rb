require "spec_helper"

RSpec.describe ModelContextProtocol::Server::ResourceTemplate do
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
