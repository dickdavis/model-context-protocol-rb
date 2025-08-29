class TestToolWithResourceResponseDefaultMimeType < ModelContextProtocol::Server::Tool
  with_metadata do
    name "note-creator"
    description "Creates a note at the specified location"
    input_schema do
      {
        type: "object",
        properties: {
          title: {
            type: "string",
            description: "Title of the note"
          },
          content: {
            type: "string",
            description: "Content of the note"
          }
        },
        required: ["title", "content"]
      }
    end
  end

  def call
    # In a real implementation, we would create an actual file
    note_uri = "note://notes/#{params[:title].downcase.gsub(/\s+/, "-")}"
    respond_with :resource, uri: note_uri, text: params[:content]
  end
end
