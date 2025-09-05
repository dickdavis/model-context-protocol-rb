module ModelContextProtocol
  module Server::ContentHelpers
    def text_content(text:, meta: nil, annotations: {})
      serialized_annotations = ModelContextProtocol::Server::Content::Annotations[
        audience: annotations[:audience],
        last_modified: annotations[:last_modified],
        priority: annotations[:priority]
      ].serialized

      ModelContextProtocol::Server::Content::Text[
        meta:,
        annotations: serialized_annotations,
        text:
      ]
    end

    def image_content(data:, mime_type:, meta: nil, annotations: {})
      serialized_annotations = ModelContextProtocol::Server::Content::Annotations[
        audience: annotations[:audience],
        last_modified: annotations[:last_modified],
        priority: annotations[:priority]
      ].serialized

      ModelContextProtocol::Server::Content::Image[
        meta:,
        annotations: serialized_annotations,
        data:,
        mime_type:
      ]
    end

    def audio_content(data:, mime_type:, meta: nil, annotations: {})
      serialized_annotations = ModelContextProtocol::Server::Content::Annotations[
        audience: annotations[:audience],
        last_modified: annotations[:last_modified],
        priority: annotations[:priority]
      ].serialized

      ModelContextProtocol::Server::Content::Audio[
        meta:,
        annotations: serialized_annotations,
        data:,
        mime_type:
      ]
    end

    def embedded_resource_content(resource:)
      extracted_resource = resource.serialized[:contents].first
      annotations = extracted_resource.key?(:annotations) ? extracted_resource.delete(:annotations) : {}

      serialized_annotations = ModelContextProtocol::Server::Content::Annotations[
        audience: annotations[:audience],
        last_modified: annotations[:lastModified],
        priority: annotations[:priority]
      ].serialized

      extracted_resource[:annotations] = serialized_annotations if serialized_annotations

      ModelContextProtocol::Server::Content::EmbeddedResource[
        meta: nil,
        resource: extracted_resource
      ]
    end

    def resource_link(name:, uri:, meta: nil, annotations: {}, description: nil, mime_type: nil, size: nil, title: nil)
      serialized_annotations = ModelContextProtocol::Server::Content::Annotations[
        audience: annotations[:audience],
        last_modified: annotations[:last_modified],
        priority: annotations[:priority]
      ].serialized

      ModelContextProtocol::Server::Content::ResourceLink[
        meta:,
        annotations: serialized_annotations,
        description:,
        mime_type:,
        name:,
        size:,
        title:,
        uri:
      ].serialized
    end
  end
end
