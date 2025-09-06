require "spec_helper"

RSpec.describe ModelContextProtocol::Server::Resource do
  describe ".call" do
    it "returns the response from the instance's call method" do
      response = TestResource.call
      aggregate_failures do
        expect(response.text).to eq("I'm finna eat all my wife's leftovers.")
        expect(response.serialized).to eq(
          contents: [
            {
              mimeType: "text/plain",
              text: "I'm finna eat all my wife's leftovers.",
              title: "Top Secret Plans",
              uri: "file:///top-secret-plans.txt"
            }
          ]
        )
      end
    end
  end

  describe "#initialize" do
    it "sets mime_type and uri from class definition" do
      resource = TestResource.new
      expect(resource.mime_type).to eq("text/plain")
      expect(resource.uri).to eq("file:///top-secret-plans.txt")
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
              text: "I'm finna eat all my wife's leftovers.",
              title: "Top Secret Plans",
              uri: "file:///top-secret-plans.txt"
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
              mimeType: "image/png",
              uri: "file:///project-logo.png"
            }
          ]
        )
      end
    end
  end

  describe "define" do
    it "sets the class definition" do
      aggregate_failures do
        expect(TestResource.name).to eq("top-secret-plans.txt")
        expect(TestResource.description).to eq("Top secret plans to do top secret things")
        expect(TestResource.mime_type).to eq("text/plain")
        expect(TestResource.uri).to eq("file:///top-secret-plans.txt")
      end
    end
  end

  describe "definition" do
    it "returns class definition" do
      expect(TestResource.definition).to eq(
        name: "top-secret-plans.txt",
        title: "Top Secret Plans",
        description: "Top secret plans to do top secret things",
        mimeType: "text/plain",
        uri: "file:///top-secret-plans.txt"
      )
    end
  end

  describe "annotations" do
    describe "with annotations" do
      it "includes annotations in definition" do
        expect(TestAnnotatedResource.definition).to include(
          annotations: {
            audience: ["user", "assistant"],
            priority: 0.9,
            lastModified: "2025-01-12T15:00:58Z"
          }
        )
      end

      it "includes annotations in serialized response" do
        response = TestAnnotatedResource.call

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
      it "does not include annotations in definition" do
        expect(TestResource.definition).not_to have_key(:annotations)
      end

      it "does not include annotations in serialized response" do
        response = TestResource.call

        content = response.serialized[:contents].first
        expect(content).not_to have_key(:annotations)
      end
    end

    describe "AnnotationsDSL" do
      describe "audience validation" do
        it "accepts valid audience values" do
          expect {
            Class.new(ModelContextProtocol::Server::Resource) do
              define do
                annotations do
                  audience :user
                end
              end
            end
          }.not_to raise_error
        end

        it "accepts array of valid audience values" do
          expect {
            Class.new(ModelContextProtocol::Server::Resource) do
              define do
                annotations do
                  audience [:user, :assistant]
                end
              end
            end
          }.not_to raise_error
        end

        it "rejects invalid audience values" do
          expect {
            Class.new(ModelContextProtocol::Server::Resource) do
              define do
                annotations do
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
              define do
                annotations do
                  priority 0.5
                end
              end
            end
          }.not_to raise_error
        end

        it "rejects priority below 0" do
          expect {
            Class.new(ModelContextProtocol::Server::Resource) do
              define do
                annotations do
                  priority(-0.1)
                end
              end
            end
          }.to raise_error(ArgumentError, /Priority must be a number between 0.0 and 1.0/)
        end

        it "rejects priority above 1" do
          expect {
            Class.new(ModelContextProtocol::Server::Resource) do
              define do
                annotations do
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
              define do
                annotations do
                  last_modified "2025-01-12T15:00:58Z"
                end
              end
            end
          }.not_to raise_error
        end

        it "rejects invalid date format" do
          expect {
            Class.new(ModelContextProtocol::Server::Resource) do
              define do
                annotations do
                  last_modified "not-a-date"
                end
              end
            end
          }.to raise_error(ArgumentError, /lastModified must be in ISO 8601 format/)
        end
      end
    end
  end

  describe "optional title field" do
    let(:resource_without_title) do
      Class.new(ModelContextProtocol::Server::Resource) do
        define do
          name "test-resource"
          description "A test resource without title"
          mime_type "text/plain"
          uri "file:///test-resource"
        end

        def call
          respond_with text: "test content"
        end
      end
    end

    it "does not include title in definition when not provided" do
      metadata = resource_without_title.definition
      expect(metadata).not_to have_key(:title)
    end

    it "does not include title in serialized response when not provided" do
      response = resource_without_title.call
      content = response.serialized[:contents].first
      expect(content).not_to have_key(:title)
    end
  end
end
