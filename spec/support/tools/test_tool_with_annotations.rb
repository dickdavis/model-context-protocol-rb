class TestToolWithAnnotations < ModelContextProtocol::Server::Tool
  define do
    name "fetch"
    description "Fetch the full contents of a single resource"
    input_schema do
      {
        type: "object",
        properties: {
          id: {
            type: "string",
            description: "Unique identifier of the resource to fetch"
          }
        },
        required: ["id"]
      }
    end
    annotations do
      {readOnlyHint: true}
    end
  end

  def call
    id = arguments[:id]
    client_logger.info("Fetching resource #{id}")

    respond_with content: text_content(text: "Contents of resource #{id}")
  end
end
