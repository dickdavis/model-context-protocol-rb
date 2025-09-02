require "spec_helper"

RSpec.describe ModelContextProtocol::Server::Resource do
  describe ".call" do
    it "returns the response from the instance's call method" do
      logger = double("logger")
      response = TestResource.call(logger)
      aggregate_failures do
        expect(response.text).to eq("Nothing to see here, move along.")
        expect(response.serialized).to eq(
          contents: [
            {
              mimeType: "text/plain",
              text: "Nothing to see here, move along.",
              uri: "file:///top-secret-plans.txt"
            }
          ]
        )
      end
    end
  end

  describe ".call with context" do
    let(:context) { {user_id: "123456"} }

    it "passes context to the instance" do
      logger = double("logger")
      allow(TestResource).to receive(:new).with(logger, context).and_call_original
      response = TestResource.call(logger, context)
      expect(response.text).to eq("I'm finna eat all my wife's leftovers.")
    end

    it "works with empty context" do
      logger = double("logger")
      response = TestResource.call(logger, {})
      expect(response.text).to eq("Nothing to see here, move along.")
    end

    it "works when context is not provided" do
      logger = double("logger")
      response = TestResource.call(logger)
      expect(response.text).to eq("Nothing to see here, move along.")
    end
  end

  describe "#initialize" do
    it "stores context when provided" do
      context = {user_id: "123"}
      logger = double("logger")
      resource = TestResource.new(logger, context)
      expect(resource.context).to eq(context)
    end

    it "defaults to empty hash when no context provided" do
      logger = double("logger")
      resource = TestResource.new(logger)
      expect(resource.context).to eq({})
    end

    it "sets mime_type and uri from class metadata" do
      logger = double("logger")
      resource = TestResource.new(logger)
      expect(resource.mime_type).to eq("text/plain")
      expect(resource.uri).to eq("file:///top-secret-plans.txt")
    end
  end

  describe "responses" do
    describe "text response" do
      it "formats text responses correctly" do
        logger = double("logger")
        response = TestResource.call(logger)
        expect(response.serialized).to eq(
          contents: [
            {
              mimeType: "text/plain",
              text: "Nothing to see here, move along.",
              uri: "file:///top-secret-plans.txt"
            }
          ]
        )
      end
    end

    describe "binary response" do
      it "formats binary responses correctly" do
        logger = double("logger")
        response = TestBinaryResource.call(logger)

        expect(response.serialized).to eq(
          contents: [
            {
              blob: "dGVzdA==",
              mimeType: "image/png",
              uri: "file:///project-logo.png"
            }
          ]
        )
      end
    end
  end

  describe "with_metadata" do
    it "sets the class metadata" do
      aggregate_failures do
        expect(TestResource.name).to eq("top-secret-plans.txt")
        expect(TestResource.description).to eq("Top secret plans to do top secret things")
        expect(TestResource.mime_type).to eq("text/plain")
        expect(TestResource.uri).to eq("file:///top-secret-plans.txt")
      end
    end
  end

  describe "metadata" do
    it "returns class metadata" do
      expect(TestResource.metadata).to eq(
        name: "top-secret-plans.txt",
        description: "Top secret plans to do top secret things",
        mimeType: "text/plain",
        uri: "file:///top-secret-plans.txt"
      )
    end
  end
end
