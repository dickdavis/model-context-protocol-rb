class TestToolWithResourceResponse < ModelContextProtocol::Server::Tool
  with_metadata do
    name "document-finder"
    description "Finds a the document with the given title"
    input_schema do
      {
        type: "object",
        properties: {
          title: {
            type: "string",
            description: "The title of the document"
          }
        },
        required: ["title"]
      }
    end
  end

  def call
    title = params["title"].downcase
    # In a real implementation, we would do a lookup to get the document data
    document = "richtextdata"
    respond_with :resource, uri: "resource://document/#{title}", text: document, mime_type: "application/rtf"
  end
end
