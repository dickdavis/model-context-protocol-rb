class TestToolWithResourceLinkResponse < ModelContextProtocol::Server::Tool
  define do
    name "document-finder"
    description "Finds documents and returns resource links"
    input_schema do
      {
        type: "object",
        properties: {
          name: {
            type: "string",
            description: "The name of the document to find"
          }
        },
        required: ["name"]
      }
    end
  end

  def call
    name = arguments[:name]

    # Create ResourceLink content object directly since the helper returns serialized form
    link = ModelContextProtocol::Server::Content::ResourceLink[
      meta: nil,
      annotations: nil,
      description: "A document named #{name}",
      mime_type: "text/markdown",
      name: name,
      size: nil,
      title: "Document: #{name}",
      uri: "file:///docs/#{name}.md"
    ]

    respond_with content: link
  end
end
