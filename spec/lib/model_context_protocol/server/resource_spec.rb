require "spec_helper"

RSpec.describe ModelContextProtocol::Server::Resource do
  describe ".call" do
    it "returns the response from the instance's call method" do
      response = TestResource.call
      expect(response).to eq(
        contents: [
          {
            mimeType: "text/plain",
            text: "Here's the data",
            uri: "resource://test-resource"
          }
        ]
      )
    end
  end

  describe "data objects for responses" do
    describe "TextResponse" do
      it "formats text responses correctly" do
        response = described_class::TextResponse[text: "Hello", resource: TestResource.new]
        expect(response.serialized).to eq(
          contents: [
            {
              mimeType: "text/plain",
              text: "Hello",
              uri: "resource://test-resource"
            }
          ]
        )
      end
    end

    describe "BinaryResponse" do
      it "formats binary responses correctly" do
        response = described_class::BinaryResponse[blob: "base64data", resource: TestBinaryResource.new]

        expect(response.serialized).to eq(
          contents: [
            {
              blob: "base64data",
              mimeType: "image/jpeg",
              uri: "resource://test-resource"
            }
          ]
        )
      end
    end
  end

  describe "with_metadata" do
    it "sets the class metadata" do
      aggregate_failures do
        expect(TestResource.name).to eq("Test Resource")
        expect(TestResource.description).to eq("A test resource")
        expect(TestResource.mime_type).to eq("text/plain")
        expect(TestResource.uri).to eq("resource://test-resource")
      end
    end
  end

  describe "metadata" do
    it "returns class metadata" do
      expect(TestResource.metadata).to eq(
        name: "Test Resource",
        description: "A test resource",
        mime_type: "text/plain",
        uri: "resource://test-resource"
      )
    end
  end
end
