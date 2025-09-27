require "spec_helper"

RSpec.describe ModelContextProtocol::Server::ContentHelpers do
  # Create a test class that includes the module
  let(:test_class) do
    Class.new do
      include ModelContextProtocol::Server::ContentHelpers
    end
  end

  let(:helper) { test_class.new }
  let(:client_logger) { double("client_logger") }
  let(:server_logger) { ModelContextProtocol::Server::ServerLogger.new }

  before do
    allow(client_logger).to receive(:info)
  end

  describe "#text_content" do
    context "with valid data" do
      it "returns a Text content object with required parameters" do
        result = helper.text_content(text: "Hello world")

        expect(result).to be_a(ModelContextProtocol::Server::Content::Text)
        expect(result.text).to eq("Hello world")
        expect(result.meta).to be_nil
        expect(result.annotations).to be_nil
      end

      it "returns a Text content object with meta" do
        result = helper.text_content(text: "Hello world", meta: {source: "test"})

        expect(result).to be_a(ModelContextProtocol::Server::Content::Text)
        expect(result.text).to eq("Hello world")
        expect(result.meta).to eq({source: "test"})
        expect(result.annotations).to be_nil
      end

      it "returns a Text content object with annotations" do
        annotations = {audience: "user", priority: 0.8}
        result = helper.text_content(text: "Hello world", annotations: annotations)

        expect(result).to be_a(ModelContextProtocol::Server::Content::Text)
        expect(result.text).to eq("Hello world")
        expect(result.meta).to be_nil
        expect(result.annotations).to eq({audience: "user", priority: 0.8})
      end

      it "returns a Text content object with all parameters" do
        annotations = {audience: ["user", "assistant"], last_modified: "2025-01-12T15:00:58Z", priority: 1.0}
        result = helper.text_content(
          text: "Hello world",
          meta: {id: 123},
          annotations: annotations
        )

        expect(result).to be_a(ModelContextProtocol::Server::Content::Text)
        expect(result.text).to eq("Hello world")
        expect(result.meta).to eq({id: 123})
        expect(result.annotations).to eq({
          audience: ["user", "assistant"],
          lastModified: "2025-01-12T15:00:58Z",
          priority: 1.0
        })
      end
    end
  end

  describe "#image_content" do
    context "with valid data" do
      it "returns an Image content object with required parameters" do
        result = helper.image_content(data: "base64data", mime_type: "image/png")

        expect(result).to be_a(ModelContextProtocol::Server::Content::Image)
        expect(result.data).to eq("base64data")
        expect(result.mime_type).to eq("image/png")
        expect(result.meta).to be_nil
        expect(result.annotations).to be_nil
      end

      it "returns an Image content object with meta" do
        result = helper.image_content(
          data: "base64data",
          mime_type: "image/jpeg",
          meta: {camera: "front"}
        )

        expect(result).to be_a(ModelContextProtocol::Server::Content::Image)
        expect(result.data).to eq("base64data")
        expect(result.mime_type).to eq("image/jpeg")
        expect(result.meta).to eq({camera: "front"})
        expect(result.annotations).to be_nil
      end

      it "returns an Image content object with annotations" do
        annotations = {audience: "assistant", priority: 0.5}
        result = helper.image_content(
          data: "base64data",
          mime_type: "image/gif",
          annotations: annotations
        )

        expect(result).to be_a(ModelContextProtocol::Server::Content::Image)
        expect(result.data).to eq("base64data")
        expect(result.mime_type).to eq("image/gif")
        expect(result.meta).to be_nil
        expect(result.annotations).to eq({audience: "assistant", priority: 0.5})
      end

      it "returns an Image content object with all parameters" do
        annotations = {audience: "user", last_modified: "2025-01-12T15:00:58.123Z"}
        result = helper.image_content(
          data: "base64data",
          mime_type: "image/webp",
          meta: {width: 800, height: 600},
          annotations: annotations
        )

        expect(result).to be_a(ModelContextProtocol::Server::Content::Image)
        expect(result.data).to eq("base64data")
        expect(result.mime_type).to eq("image/webp")
        expect(result.meta).to eq({width: 800, height: 600})
        expect(result.annotations).to eq({
          audience: "user",
          lastModified: "2025-01-12T15:00:58.123Z"
        })
      end
    end
  end

  describe "#audio_content" do
    context "with valid data" do
      it "returns an Audio content object with required parameters" do
        result = helper.audio_content(data: "base64audio", mime_type: "audio/mp3")

        expect(result).to be_a(ModelContextProtocol::Server::Content::Audio)
        expect(result.data).to eq("base64audio")
        expect(result.mime_type).to eq("audio/mp3")
        expect(result.meta).to be_nil
        expect(result.annotations).to be_nil
      end

      it "returns an Audio content object with meta" do
        result = helper.audio_content(
          data: "base64audio",
          mime_type: "audio/wav",
          meta: {duration: 120}
        )

        expect(result).to be_a(ModelContextProtocol::Server::Content::Audio)
        expect(result.data).to eq("base64audio")
        expect(result.mime_type).to eq("audio/wav")
        expect(result.meta).to eq({duration: 120})
        expect(result.annotations).to be_nil
      end

      it "returns an Audio content object with annotations" do
        annotations = {audience: ["user"], priority: 0.9}
        result = helper.audio_content(
          data: "base64audio",
          mime_type: "audio/ogg",
          annotations: annotations
        )

        expect(result).to be_a(ModelContextProtocol::Server::Content::Audio)
        expect(result.data).to eq("base64audio")
        expect(result.mime_type).to eq("audio/ogg")
        expect(result.meta).to be_nil
        expect(result.annotations).to eq({audience: ["user"], priority: 0.9})
      end

      it "returns an Audio content object with all parameters" do
        annotations = {audience: "assistant", last_modified: "2025-01-12T15:00:58Z", priority: 0.7}
        result = helper.audio_content(
          data: "base64audio",
          mime_type: "audio/flac",
          meta: {bitrate: 320, duration: 240},
          annotations: annotations
        )

        expect(result).to be_a(ModelContextProtocol::Server::Content::Audio)
        expect(result.data).to eq("base64audio")
        expect(result.mime_type).to eq("audio/flac")
        expect(result.meta).to eq({bitrate: 320, duration: 240})
        expect(result.annotations).to eq({
          audience: "assistant",
          lastModified: "2025-01-12T15:00:58Z",
          priority: 0.7
        })
      end
    end
  end

  describe "#embedded_resource_content" do
    context "with valid data" do
      it "returns an EmbeddedResource content object" do
        resource_data = TestResource.call(client_logger, server_logger)
        result = helper.embedded_resource_content(resource: resource_data)

        aggregate_failures do
          expect(result).to be_a(ModelContextProtocol::Server::Content::EmbeddedResource)
          expect(result.resource).to eq(resource_data.serialized[:contents].first)
        end
      end

      it "returns an EmbeddedResource content object with annotations" do
        resource_data = TestResource.call(client_logger, server_logger)
        result = helper.embedded_resource_content(resource: resource_data)

        aggregate_failures do
          expect(result).to be_a(ModelContextProtocol::Server::Content::EmbeddedResource)
          expect(result.resource).to eq(resource_data.serialized[:contents].first)
        end
      end
    end
  end

  describe "#resource_link" do
    context "with valid data" do
      it "returns a serialized ResourceLink hash with required parameters" do
        result = helper.resource_link(name: "test-file", uri: "https://example.com/test.txt")

        expect(result).to be_a(Hash)
        expect(result[:name]).to eq("test-file")
        expect(result[:uri]).to eq("https://example.com/test.txt")
        expect(result[:type]).to eq("resource_link")
      end

      it "returns a serialized ResourceLink hash with meta" do
        result = helper.resource_link(
          name: "test-file",
          uri: "https://example.com/test.txt",
          meta: {api_version: "v1"}
        )

        expect(result).to be_a(Hash)
        expect(result[:name]).to eq("test-file")
        expect(result[:uri]).to eq("https://example.com/test.txt")
        expect(result[:type]).to eq("resource_link")
        expect(result[:_meta]).to eq({api_version: "v1"})
      end

      it "returns a serialized ResourceLink hash with annotations" do
        annotations = {audience: "user", priority: 0.8}
        result = helper.resource_link(
          name: "test-file",
          uri: "https://example.com/test.txt",
          annotations: annotations
        )

        expect(result).to be_a(Hash)
        expect(result[:name]).to eq("test-file")
        expect(result[:uri]).to eq("https://example.com/test.txt")
        expect(result[:type]).to eq("resource_link")
        expect(result[:annotations]).to eq({audience: "user", priority: 0.8})
      end

      it "returns a serialized ResourceLink hash with all optional parameters" do
        annotations = {audience: ["user", "assistant"], last_modified: "2025-01-12T15:00:58Z", priority: 1.0}
        result = helper.resource_link(
          name: "test-file",
          uri: "https://example.com/test.txt",
          meta: {external: true},
          annotations: annotations,
          description: "A test file",
          mime_type: "text/plain",
          size: 1024,
          title: "Test File"
        )

        expect(result).to be_a(Hash)
        expect(result[:name]).to eq("test-file")
        expect(result[:uri]).to eq("https://example.com/test.txt")
        expect(result[:type]).to eq("resource_link")
        expect(result[:_meta]).to eq({external: true})
        expect(result[:annotations]).to eq({
          audience: ["user", "assistant"],
          lastModified: "2025-01-12T15:00:58Z",
          priority: 1.0
        })
        expect(result[:description]).to eq("A test file")
        expect(result[:mimeType]).to eq("text/plain")
        expect(result[:size]).to eq(1024)
        expect(result[:title]).to eq("Test File")
      end

      it "returns a serialized ResourceLink hash with only some optional parameters" do
        result = helper.resource_link(
          name: "test-file",
          uri: "https://example.com/test.txt",
          description: "A test file",
          size: 2048
        )

        expect(result).to be_a(Hash)
        expect(result[:name]).to eq("test-file")
        expect(result[:uri]).to eq("https://example.com/test.txt")
        expect(result[:type]).to eq("resource_link")
        expect(result[:description]).to eq("A test file")
        expect(result[:size]).to eq(2048)
        expect(result).not_to have_key(:_meta)
        expect(result).not_to have_key(:annotations)
        expect(result).not_to have_key(:mimeType)
        expect(result).not_to have_key(:title)
      end
    end
  end
end
