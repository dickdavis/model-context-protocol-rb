require "spec_helper"

RSpec.describe ModelContextProtocol::Server::Resource do
  describe ".call" do
    it "returns the response from the instance's call method" do
      response = TestResource.call
      aggregate_failures do
        expect(response.text).to eq("Here's the data")
        expect(response.serialized).to eq(
          contents: [
            {
              mimeType: "text/plain",
              text: "Here's the data",
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
        response = TestResource.call
        expect(response.serialized).to eq(
          contents: [
            {
              mimeType: "text/plain",
              text: "Here's the data",
              uri: "resource:///test-resource"
            }
          ]
        )
      end
    end

    describe "binary response" do
      it "formats binary responses correctly" do
        response = TestBinaryResource.call

        expect(response.serialized).to eq(
          contents: [
            {
              blob: "dGVzdA==",
              mimeType: "image/jpeg",
              uri: "resource:///project-logo"
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
        expect(TestResource.uri).to eq("resource:///test-resource")
      end
    end
  end

  describe "metadata" do
    it "returns class metadata" do
      expect(TestResource.metadata).to eq(
        name: "Test Resource",
        description: "A test resource",
        mimeType: "text/plain",
        uri: "resource:///test-resource"
      )
    end
  end
end
