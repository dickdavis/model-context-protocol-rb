require "spec_helper"

RSpec.describe ModelContextProtocol::Server::ResourceTemplate do
  describe "with_metadata" do
    it "sets the class metadata" do
      aggregate_failures do
        expect(TestResourceTemplate.name).to eq("project-document-resource-template")
        expect(TestResourceTemplate.description).to eq("A resource template for retrieving project documents")
        expect(TestResourceTemplate.mime_type).to eq("text/plain")
        expect(TestResourceTemplate.uri_template).to eq("file:///{name}")
        expect(TestResourceTemplate.completions).to eq({"name" => TestResourceTemplate::Completion})
      end
    end
  end

  describe "metadata" do
    it "returns class metadata" do
      expect(TestResourceTemplate.metadata).to eq(
        name: "project-document-resource-template",
        description: "A resource template for retrieving project documents",
        mimeType: "text/plain",
        uriTemplate: "file:///{name}",
        completions: {"name" => TestResourceTemplate::Completion}
      )
    end
  end
end
