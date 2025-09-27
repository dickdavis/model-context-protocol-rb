require "spec_helper"

RSpec.describe ModelContextProtocol::Server::Resource do
  let(:client_logger) { double("client_logger") }
  let(:server_logger) { ModelContextProtocol::Server::ServerLogger.new }

  before do
    allow(client_logger).to receive(:info)
  end

  describe ".call" do
    it "returns the response from the instance's call method" do
      response = TestResource.call(client_logger, server_logger)
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
      resource = TestResource.new(client_logger, server_logger)

      aggregate_failures do
        expect(resource.mime_type).to eq("text/plain")
        expect(resource.uri).to eq("file:///top-secret-plans.txt")
      end
    end

    it "stores the client_logger and context" do
      context = {user_id: "test-user"}
      resource = TestResource.new(client_logger, server_logger, context)

      aggregate_failures do
        expect(resource.client_logger).to eq(client_logger)
        expect(resource.context).to eq(context)
      end
    end

    it "defaults to empty context when not provided" do
      resource = TestResource.new(client_logger, server_logger)
      expect(resource.context).to eq({})
    end
  end

  describe "responses" do
    describe "text response" do
      it "formats text responses correctly" do
        response = TestResource.call(client_logger, server_logger)
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
        response = TestBinaryResource.call(client_logger, server_logger)

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
        response = TestAnnotatedResource.call(client_logger, server_logger)

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
        response = TestResource.call(client_logger, server_logger)

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

  describe "client logger integration" do
    it "calls client_logger.info during execution" do
      expect(client_logger).to receive(:info).with("Accessing top secret plans")

      TestResource.call(client_logger, server_logger)
    end

    it "uses context values in logging" do
      context = {user_id: "test-user-123"}
      aggregate_failures do
        expect(client_logger).to receive(:info).with("Accessing top secret plans")
        expect(client_logger).to receive(:info).with("User test-user-123 is accessing secret plans")
      end

      TestResource.call(client_logger, server_logger, context)
    end

    it "handles empty context gracefully" do
      expect(client_logger).to receive(:info).with("Accessing top secret plans")

      TestResource.call(client_logger, server_logger, {})
    end
  end

  describe "server logger integration" do
    it "calls server_logger during execution" do
      aggregate_failures do
        expect(server_logger).to receive(:debug).with("Resource access requested")
        expect(server_logger).to receive(:info).with("Serving top secret plans content")
      end

      TestResource.call(client_logger, server_logger)
    end

    it "uses context values in server logging" do
      context = {user_id: "test-user-123"}
      aggregate_failures do
        expect(server_logger).to receive(:debug).with("Resource access requested")
        expect(server_logger).to receive(:info).with("Serving top secret plans content")
        expect(server_logger).to receive(:info).with("User test-user-123 accessed secret plans resource")
      end

      TestResource.call(client_logger, server_logger, context)
    end

    it "handles empty context gracefully in server logging" do
      aggregate_failures do
        expect(server_logger).to receive(:debug).with("Resource access requested")
        expect(server_logger).to receive(:info).with("Serving top secret plans content")
      end

      TestResource.call(client_logger, server_logger, {})
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
      response = resource_without_title.call(client_logger, server_logger)
      content = response.serialized[:contents].first
      expect(content).not_to have_key(:title)
    end
  end
end
