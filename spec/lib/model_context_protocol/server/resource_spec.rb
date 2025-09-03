require "spec_helper"

RSpec.describe ModelContextProtocol::Server::Resource do
  describe ".call" do
    it "returns the response from the instance's call method" do
      logger = double("logger")
      allow(logger).to receive(:info)
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
      allow(logger).to receive(:info)
      allow(TestResource).to receive(:new).with(logger, context).and_call_original
      response = TestResource.call(logger, context)
      expect(response.text).to eq("I'm finna eat all my wife's leftovers.")
    end

    it "works with empty context" do
      logger = double("logger")
      allow(logger).to receive(:info)
      response = TestResource.call(logger, {})
      expect(response.text).to eq("Nothing to see here, move along.")
    end

    it "works when context is not provided" do
      logger = double("logger")
      allow(logger).to receive(:info)
      response = TestResource.call(logger)
      expect(response.text).to eq("Nothing to see here, move along.")
    end
  end

  describe "#initialize" do
    it "stores context when provided" do
      context = {user_id: "123"}
      logger = double("logger")
      allow(logger).to receive(:info)
      resource = TestResource.new(logger, context)
      expect(resource.context).to eq(context)
    end

    it "defaults to empty hash when no context provided" do
      logger = double("logger")
      allow(logger).to receive(:info)
      resource = TestResource.new(logger)
      expect(resource.context).to eq({})
    end

    it "sets mime_type and uri from class metadata" do
      logger = double("logger")
      allow(logger).to receive(:info)
      resource = TestResource.new(logger)
      expect(resource.mime_type).to eq("text/plain")
      expect(resource.uri).to eq("file:///top-secret-plans.txt")
    end
  end

  describe "responses" do
    describe "text response" do
      it "formats text responses correctly" do
        logger = double("logger")
        allow(logger).to receive(:info)
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
        allow(logger).to receive(:info)
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

  describe "annotations" do
    describe "with annotations" do
      it "includes annotations in metadata" do
        expect(TestAnnotatedResource.metadata).to include(
          annotations: {
            audience: ["user", "assistant"],
            priority: 0.9,
            lastModified: "2025-01-12T15:00:58Z"
          }
        )
      end

      it "includes annotations in serialized response" do
        logger = double("logger")
        response = TestAnnotatedResource.call(logger)

        expect(response.serialized).to eq(
          contents: [
            {
              mimeType: "text/markdown",
              text: "# Annotated Document\n\nThis document has annotations.",
              uri: "file:///docs/annotated-document.md",
              annotations: {
                audience: ["user", "assistant"],
                priority: 0.9,
                lastModified: "2025-01-12T15:00:58Z"
              }
            }
          ]
        )
      end
    end

    describe "without annotations" do
      it "does not include annotations in metadata" do
        expect(TestResource.metadata).not_to have_key(:annotations)
      end

      it "does not include annotations in serialized response" do
        logger = double("logger")
        allow(logger).to receive(:info)
        response = TestResource.call(logger)

        content = response.serialized[:contents].first
        expect(content).not_to have_key(:annotations)
      end
    end

    describe "AnnotationsDSL" do
      describe "audience validation" do
        it "accepts valid audience values" do
          expect {
            Class.new(ModelContextProtocol::Server::Resource) do
              with_metadata do
                with_annotations do
                  audience :user
                end
              end
            end
          }.not_to raise_error
        end

        it "accepts array of valid audience values" do
          expect {
            Class.new(ModelContextProtocol::Server::Resource) do
              with_metadata do
                with_annotations do
                  audience [:user, :assistant]
                end
              end
            end
          }.not_to raise_error
        end

        it "rejects invalid audience values" do
          expect {
            Class.new(ModelContextProtocol::Server::Resource) do
              with_metadata do
                with_annotations do
                  audience :invalid
                end
              end
            end
          }.to raise_error(ArgumentError, /Invalid audience values: invalid/)
        end
      end

      describe "priority validation" do
        it "accepts valid priority values" do
          expect {
            Class.new(ModelContextProtocol::Server::Resource) do
              with_metadata do
                with_annotations do
                  priority 0.5
                end
              end
            end
          }.not_to raise_error
        end

        it "rejects priority below 0" do
          expect {
            Class.new(ModelContextProtocol::Server::Resource) do
              with_metadata do
                with_annotations do
                  priority(-0.1)
                end
              end
            end
          }.to raise_error(ArgumentError, /Priority must be a number between 0.0 and 1.0/)
        end

        it "rejects priority above 1" do
          expect {
            Class.new(ModelContextProtocol::Server::Resource) do
              with_metadata do
                with_annotations do
                  priority 1.1
                end
              end
            end
          }.to raise_error(ArgumentError, /Priority must be a number between 0.0 and 1.0/)
        end
      end

      describe "last_modified validation" do
        it "accepts valid ISO 8601 format" do
          expect {
            Class.new(ModelContextProtocol::Server::Resource) do
              with_metadata do
                with_annotations do
                  last_modified "2025-01-12T15:00:58Z"
                end
              end
            end
          }.not_to raise_error
        end

        it "rejects invalid date format" do
          expect {
            Class.new(ModelContextProtocol::Server::Resource) do
              with_metadata do
                with_annotations do
                  last_modified "not-a-date"
                end
              end
            end
          }.to raise_error(ArgumentError, /lastModified must be in ISO 8601 format/)
        end
      end
    end
  end
end
