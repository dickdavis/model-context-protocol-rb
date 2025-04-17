class TestBinaryResourceTemplate < ModelContextProtocol::Server::ResourceTemplate
  with_metadata do
    {
      name: "Image Search",
      description: "Returns an image given a filename",
      mime_type: "image/jpeg",
      uri_template: "resource://{filename}"
    }
  end

  def call
    # In a real implementation, we would retrieve the binary resource using extracted_uri["filename"]
    data = "dGVzdA=="
    respond_with :binary, blob: data
  end
end
