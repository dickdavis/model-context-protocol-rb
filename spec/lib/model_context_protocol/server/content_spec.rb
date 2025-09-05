require "spec_helper"

RSpec.describe ModelContextProtocol::Server::Content do
  describe ModelContextProtocol::Server::Content::Text do
    describe "#serialized" do
      context "with valid data" do
        it "returns a valid hash with required fields" do
          text = described_class.new(meta: nil, annotations: nil, text: "Hello world")
          result = text.serialized

          expect(result).to eq({
            text: "Hello world",
            type: "text"
          })
        end

        it "returns a valid hash with meta and annotations" do
          annotations = ModelContextProtocol::Server::Content::Annotations.new(
            audience: "user",
            last_modified: nil,
            priority: nil
          ).serialized

          text = described_class.new(
            meta: {custom: "data"},
            annotations: annotations,
            text: "Hello world"
          )
          result = text.serialized

          expect(result).to eq({
            _meta: {custom: "data"},
            annotations: {audience: "user"},
            text: "Hello world",
            type: "text"
          })
        end
      end

      context "with invalid data" do
        it "raises ContentValidationError when text is missing" do
          text = described_class.new(meta: nil, annotations: nil, text: nil)

          expect { text.serialized }.to raise_error(
            ModelContextProtocol::Server::Content::ContentValidationError
          )
        end

        it "raises ContentValidationError when text is not a string" do
          text = described_class.new(meta: nil, annotations: nil, text: 123)

          expect { text.serialized }.to raise_error(
            ModelContextProtocol::Server::Content::ContentValidationError
          )
        end
      end
    end
  end

  describe ModelContextProtocol::Server::Content::Image do
    describe "#serialized" do
      context "with valid data" do
        it "returns a valid hash with required fields" do
          image = described_class.new(
            meta: nil,
            annotations: nil,
            data: "base64encodeddata",
            mime_type: "image/png"
          )
          result = image.serialized

          expect(result).to eq({
            data: "base64encodeddata",
            mimeType: "image/png",
            type: "image"
          })
        end

        it "returns a valid hash with meta and annotations" do
          annotations = ModelContextProtocol::Server::Content::Annotations.new(
            audience: ["user", "assistant"],
            last_modified: nil,
            priority: 0.8
          ).serialized
          image = described_class.new(
            meta: {source: "camera"},
            annotations: annotations,
            data: "base64encodeddata",
            mime_type: "image/jpeg"
          )
          result = image.serialized

          expect(result).to eq({
            _meta: {source: "camera"},
            annotations: {audience: ["user", "assistant"], priority: 0.8},
            data: "base64encodeddata",
            mimeType: "image/jpeg",
            type: "image"
          })
        end
      end

      context "with invalid data" do
        it "raises ContentValidationError when data is missing" do
          image = described_class.new(
            meta: nil,
            annotations: nil,
            data: nil,
            mime_type: "image/png"
          )

          expect { image.serialized }.to raise_error(
            ModelContextProtocol::Server::Content::ContentValidationError
          )
        end

        it "raises ContentValidationError when mime_type is missing" do
          image = described_class.new(
            meta: nil,
            annotations: nil,
            data: "base64encodeddata",
            mime_type: nil
          )

          expect { image.serialized }.to raise_error(
            ModelContextProtocol::Server::Content::ContentValidationError
          )
        end

        it "raises ContentValidationError when data is not a string" do
          image = described_class.new(
            meta: nil,
            annotations: nil,
            data: 123,
            mime_type: "image/png"
          )

          expect { image.serialized }.to raise_error(
            ModelContextProtocol::Server::Content::ContentValidationError
          )
        end
      end
    end
  end

  describe ModelContextProtocol::Server::Content::Audio do
    describe "#serialized" do
      context "with valid data" do
        it "returns a valid hash with required fields" do
          audio = described_class.new(
            meta: nil,
            annotations: nil,
            data: "base64encodedaudiodata",
            mime_type: "audio/mp3"
          )
          result = audio.serialized

          expect(result).to eq({
            data: "base64encodedaudiodata",
            mimeType: "audio/mp3",
            type: "audio"
          })
        end

        it "returns a valid hash with meta and annotations" do
          annotations = ModelContextProtocol::Server::Content::Annotations.new(
            audience: "assistant",
            last_modified: "2025-01-12T15:00:58Z",
            priority: nil
          ).serialized
          audio = described_class.new(
            meta: {duration: 120},
            annotations: annotations,
            data: "base64encodedaudiodata",
            mime_type: "audio/wav"
          )
          result = audio.serialized

          expect(result).to eq({
            _meta: {duration: 120},
            annotations: {audience: "assistant", lastModified: "2025-01-12T15:00:58Z"},
            data: "base64encodedaudiodata",
            mimeType: "audio/wav",
            type: "audio"
          })
        end
      end

      context "with invalid data" do
        it "raises ContentValidationError when data is missing" do
          audio = described_class.new(
            meta: nil,
            annotations: nil,
            data: nil,
            mime_type: "audio/mp3"
          )

          expect { audio.serialized }.to raise_error(
            ModelContextProtocol::Server::Content::ContentValidationError
          )
        end

        it "raises ContentValidationError when mime_type is missing" do
          audio = described_class.new(
            meta: nil,
            annotations: nil,
            data: "base64encodedaudiodata",
            mime_type: nil
          )

          expect { audio.serialized }.to raise_error(
            ModelContextProtocol::Server::Content::ContentValidationError
          )
        end
      end
    end
  end

  describe ModelContextProtocol::Server::Content::EmbeddedResource do
    describe "#serialized" do
      context "with valid data" do
        it "returns a valid hash with required fields" do
          resource = {uri: "file://test.txt", name: "test.txt"}

          embedded = described_class.new(meta: nil, resource:)
          result = embedded.serialized

          expect(result).to eq(
            {
              resource: {uri: "file://test.txt", name: "test.txt"},
              type: "resource"
            }
          )
        end

        it "returns a valid hash with annotations" do
          resource = {
            uri: "file://test.txt",
            name: "test.txt",
            annotations: {audience: ["user"], priority: 0.5}
          }
          embedded = described_class.new(meta: nil, resource:)
          result = embedded.serialized

          expect(result).to eq(
            {
              resource: {
                uri: "file://test.txt",
                name: "test.txt",
                annotations: {audience: ["user"], priority: 0.5}
              },
              type: "resource"
            }
          )
        end
      end

      context "with invalid data" do
        it "raises an error when resource is missing" do
          embedded = described_class.new(meta: nil, resource: nil)

          expect { embedded.serialized }
            .to raise_error(ModelContextProtocol::Server::Content::ContentValidationError)
        end
      end
    end
  end

  describe ModelContextProtocol::Server::Content::ResourceLink do
    describe "#serialized" do
      context "with valid data" do
        it "returns a valid hash with required fields" do
          link = described_class.new(
            meta: nil,
            annotations: nil,
            description: nil,
            mime_type: nil,
            name: "test-file",
            size: nil,
            title: nil,
            uri: "https://example.com/test.txt"
          )
          result = link.serialized

          expect(result).to eq({
            name: "test-file",
            type: "resource_link",
            uri: "https://example.com/test.txt"
          })
        end

        it "returns a valid hash with all optional fields" do
          annotations = ModelContextProtocol::Server::Content::Annotations.new(
            audience: "user",
            last_modified: "2025-01-12T15:00:58.123Z",
            priority: 1.0
          ).serialized
          link = described_class.new(
            meta: {source: "api"},
            annotations: annotations,
            description: "A test file",
            mime_type: "text/plain",
            name: "test-file",
            size: 1024,
            title: "Test File",
            uri: "https://example.com/test.txt"
          )
          result = link.serialized

          expect(result).to eq({
            _meta: {source: "api"},
            annotations: {audience: "user", lastModified: "2025-01-12T15:00:58.123Z", priority: 1.0},
            description: "A test file",
            mimeType: "text/plain",
            name: "test-file",
            size: 1024,
            title: "Test File",
            type: "resource_link",
            uri: "https://example.com/test.txt"
          })
        end
      end

      context "with invalid data" do
        it "raises ContentValidationError when name is missing" do
          link = described_class.new(
            meta: nil,
            annotations: nil,
            description: nil,
            mime_type: nil,
            name: nil,
            size: nil,
            title: nil,
            uri: "https://example.com/test.txt"
          )

          expect { link.serialized }.to raise_error(
            ModelContextProtocol::Server::Content::ContentValidationError
          )
        end

        it "raises ContentValidationError when uri is missing" do
          link = described_class.new(
            meta: nil,
            annotations: nil,
            description: nil,
            mime_type: nil,
            name: "test-file",
            size: nil,
            title: nil,
            uri: nil
          )

          expect { link.serialized }.to raise_error(
            ModelContextProtocol::Server::Content::ContentValidationError
          )
        end

        it "raises ContentValidationError when size is not a number" do
          link = described_class.new(
            meta: nil,
            annotations: nil,
            description: nil,
            mime_type: nil,
            name: "test-file",
            size: "large",
            title: nil,
            uri: "https://example.com/test.txt"
          )

          expect { link.serialized }.to raise_error(
            ModelContextProtocol::Server::Content::ContentValidationError
          )
        end
      end
    end
  end

  describe ModelContextProtocol::Server::Content::Annotations do
    describe "#serialized" do
      context "with valid data" do
        it "returns nil when all fields are nil" do
          annotations = described_class.new(audience: nil, last_modified: nil, priority: nil)
          result = annotations.serialized

          expect(result).to eq(nil)
        end

        it "returns hash with audience as string" do
          annotations = described_class.new(audience: "user", last_modified: nil, priority: nil)
          result = annotations.serialized

          expect(result).to eq({audience: "user"})
        end

        it "returns hash with audience as array" do
          annotations = described_class.new(audience: ["user", "assistant"], last_modified: nil, priority: nil)
          result = annotations.serialized

          expect(result).to eq({audience: ["user", "assistant"]})
        end

        it "returns hash with valid ISO 8601 date" do
          annotations = described_class.new(audience: nil, last_modified: "2025-01-12T15:00:58Z", priority: nil)
          result = annotations.serialized

          expect(result).to eq({lastModified: "2025-01-12T15:00:58Z"})
        end

        it "returns hash with valid ISO 8601 date with milliseconds" do
          annotations = described_class.new(audience: nil, last_modified: "2025-01-12T15:00:58.123Z", priority: nil)
          result = annotations.serialized

          expect(result).to eq({lastModified: "2025-01-12T15:00:58.123Z"})
        end

        it "returns hash with priority" do
          annotations = described_class.new(audience: nil, last_modified: nil, priority: 0.5)
          result = annotations.serialized

          expect(result).to eq({priority: 0.5})
        end

        it "returns hash with all valid fields" do
          annotations = described_class.new(
            audience: ["assistant", "user"],
            last_modified: "2025-01-12T15:00:58.999Z",
            priority: 0.9
          )
          result = annotations.serialized

          expect(result).to eq({
            audience: ["assistant", "user"],
            lastModified: "2025-01-12T15:00:58.999Z",
            priority: 0.9
          })
        end
      end

      context "with invalid data" do
        it "raises ContentValidationError with invalid audience string" do
          annotations = described_class.new(audience: "invalid", last_modified: nil, priority: nil)

          expect { annotations.serialized }.to raise_error(
            ModelContextProtocol::Server::Content::ContentValidationError
          )
        end

        it "raises ContentValidationError with invalid audience array value" do
          annotations = described_class.new(audience: ["user", "invalid"], last_modified: nil, priority: nil)

          expect { annotations.serialized }.to raise_error(
            ModelContextProtocol::Server::Content::ContentValidationError
          )
        end

        it "raises ContentValidationError with empty audience array" do
          annotations = described_class.new(audience: [], last_modified: nil, priority: nil)

          expect { annotations.serialized }.to raise_error(
            ModelContextProtocol::Server::Content::ContentValidationError
          )
        end

        it "raises ContentValidationError with too many audience values" do
          annotations = described_class.new(audience: ["user", "assistant", "system"], last_modified: nil, priority: nil)

          expect { annotations.serialized }.to raise_error(
            ModelContextProtocol::Server::Content::ContentValidationError
          )
        end

        it "raises ContentValidationError with duplicate audience values" do
          annotations = described_class.new(audience: ["user", "user"], last_modified: nil, priority: nil)

          expect { annotations.serialized }.to raise_error(
            ModelContextProtocol::Server::Content::ContentValidationError
          )
        end

        it "raises ContentValidationError with invalid date format" do
          annotations = described_class.new(audience: nil, last_modified: "2025-01-12", priority: nil)

          expect { annotations.serialized }.to raise_error(
            ModelContextProtocol::Server::Content::ContentValidationError
          )
        end

        it "raises ContentValidationError with invalid date format (no Z)" do
          annotations = described_class.new(audience: nil, last_modified: "2025-01-12T15:00:58", priority: nil)

          expect { annotations.serialized }.to raise_error(
            ModelContextProtocol::Server::Content::ContentValidationError
          )
        end

        it "raises ContentValidationError with priority below minimum" do
          annotations = described_class.new(audience: nil, last_modified: nil, priority: -0.1)

          expect { annotations.serialized }.to raise_error(
            ModelContextProtocol::Server::Content::ContentValidationError
          )
        end

        it "raises ContentValidationError with priority above maximum" do
          annotations = described_class.new(audience: nil, last_modified: nil, priority: 1.1)

          expect { annotations.serialized }.to raise_error(
            ModelContextProtocol::Server::Content::ContentValidationError
          )
        end
      end
    end
  end
end
