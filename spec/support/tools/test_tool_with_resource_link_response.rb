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

    respond_with content: resource_link(
      name: name,
      uri: "file:///docs/#{name}.md",
      description: "A document named #{name}",
      mime_type: "text/markdown",
      title: "Document: #{name}"
    )
  end
end
