require "json-schema"

module ModelContextProtocol
  module Server::Content
    class ContentValidationError < StandardError; end

    Text = Data.define(:meta, :annotations, :text) do
      def serialized
        serialized_data = {
          _meta: meta,
          annotations:,
          text:,
          type: "text"
        }.compact

        validation_errors = JSON::Validator.fully_validate(schema, serialized_data)
        if validation_errors.empty?
          serialized_data
        else
          raise ContentValidationError, validation_errors.join(", ")
        end
      end

      private

      def schema
        {
          type: "object",
          required: ["type", "text"],
          properties: {
            _meta: {
              type: "object",
              description: "Contains metadata about the content block"
            },
            annotations: {
              type: "object",
              description: "Optional metadata about the purpose and use of the content block"
            },
            text: {
              type: "string",
              description: "The text content of the content block"
            },
            type: {
              type: "string",
              description: "The type of content block",
              pattern: "^text$"
            }
          }
        }
      end
    end

    Image = Data.define(:meta, :annotations, :data, :mime_type) do
      def serialized
        serialized_data = {
          _meta: meta,
          annotations:,
          data:,
          mimeType: mime_type,
          type: "image"
        }.compact

        validation_errors = JSON::Validator.fully_validate(schema, serialized_data)
        if validation_errors.empty?
          serialized_data
        else
          raise ContentValidationError, validation_errors.join(", ")
        end
      end

      private

      def schema
        {
          type: "object",
          required: ["data", "mimeType", "type"],
          properties: {
            _meta: {
              type: "object",
              description: "Contains metadata about the content block"
            },
            annotations: {
              type: "object",
              description: "Optional metadata about the purpose and use of the content block"
            },
            data: {
              type: "string",
              description: "The base64 encoded image data"
            },
            mimeType: {
              type: "string",
              description: "The mime type associated with the image data"
            },
            type: {
              type: "string",
              description: "The type of content block",
              pattern: "^image$"
            }
          }
        }
      end
    end

    Audio = Data.define(:meta, :annotations, :data, :mime_type) do
      def serialized
        serialized_data = {
          _meta: meta,
          annotations:,
          data:,
          mimeType: mime_type,
          type: "audio"
        }.compact

        validation_errors = JSON::Validator.fully_validate(schema, serialized_data)
        if validation_errors.empty?
          serialized_data
        else
          raise ContentValidationError, validation_errors.join(", ")
        end
      end

      private

      def schema
        {
          type: "object",
          required: ["data", "mimeType", "type"],
          properties: {
            _meta: {
              type: "object",
              description: "Contains metadata about the content block"
            },
            annotations: {
              type: "object",
              description: "Optional metadata about the purpose and use of the content block"
            },
            data: {
              type: "string",
              description: "The base64 encoded image data"
            },
            mimeType: {
              type: "string",
              description: "The mime type associated with the image data"
            },
            type: {
              type: "string",
              description: "The type of content block",
              pattern: "^audio$"
            }
          }
        }
      end
    end

    EmbeddedResource = Data.define(:meta, :resource) do
      def serialized
        serialized_data = {
          _meta: meta,
          resource:,
          type: "resource"
        }.compact

        validation_errors = JSON::Validator.fully_validate(schema, serialized_data)
        if validation_errors.empty?
          serialized_data
        else
          raise ContentValidationError, validation_errors.join(", ")
        end
      end

      private

      def schema
        {
          type: "object",
          required: ["type", "resource"],
          properties: {
            _meta: {
              type: "object",
              description: "Contains metadata about the content block"
            },
            resource: {
              type: "object",
              description: "The resource embedded in the content block"
            },
            type: {
              type: "string",
              description: "The type of content block",
              pattern: "^resource$"
            }
          }
        }
      end
    end

    ResourceLink = Data.define(:meta, :annotations, :description, :mime_type, :name, :size, :title, :uri) do
      def serialized
        serialized_data = {
          _meta: meta,
          annotations:,
          description:,
          mimeType: mime_type,
          name:,
          size:,
          title:,
          type: "resource_link",
          uri:
        }.compact

        validation_errors = JSON::Validator.fully_validate(schema, serialized_data)
        if validation_errors.empty?
          serialized_data
        else
          raise ContentValidationError, validation_errors.join(", ")
        end
      end

      private

      def schema
        {
          type: "object",
          required: ["name", "type", "uri"],
          properties: {
            _meta: {
              type: "object",
              description: "Contains metadata about the content block"
            },
            annotations: {
              type: "object",
              description: "Optional metadata about the purpose and use of the content block"
            },
            description: {
              type: "string",
              description: "A description of what this resource represents"
            },
            mimeType: {
              type: "string",
              description: "The mime type of the resource in bytes (if known)"
            },
            name: {
              type: "string",
              description: "Name of the resource link, intended for programmatic use"
            },
            size: {
              type: "number",
              description: "The size of the raw resource content in bytes (if known)"
            },
            title: {
              type: "string",
              description: "Name of the resource link, intended for display purposes"
            },
            type: {
              type: "string",
              description: "The type of content block",
              pattern: "^resource_link$"
            },
            uri: {
              type: "string",
              description: "The URI of this resource"
            }
          }
        }
      end
    end

    Annotations = Data.define(:audience, :last_modified, :priority) do
      def serialized
        serialized_data = {audience:, lastModified: last_modified, priority:}.compact

        validation_errors = JSON::Validator.fully_validate(schema, serialized_data)
        unless validation_errors.empty?
          raise ContentValidationError, validation_errors.join(", ")
        end

        serialized_data.empty? ? nil : serialized_data
      end

      private

      def schema
        {
          type: "object",
          description: "Optional metadata about the purpose and use of the content block",
          properties: {
            audience: {
              oneOf: [
                {
                  type: "string",
                  enum: ["user", "assistant"]
                },
                {
                  type: "array",
                  items: {
                    type: "string",
                    enum: ["user", "assistant"]
                  },
                  minItems: 1,
                  maxItems: 2,
                  uniqueItems: true
                }
              ],
              description: "The intended audience for the content block"
            },
            lastModified: {
              type: "string",
              pattern: "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(\\.\\d{3})?Z$",
              description: "The date the content was last modified (in ISO 8601 format)"
            },
            priority: {
              type: "number",
              description: "The weight of importance the audience should place on the contents of the content block",
              minimum: 0.0,
              maximum: 1.0
            }
          }
        }
      end
    end
  end
end
