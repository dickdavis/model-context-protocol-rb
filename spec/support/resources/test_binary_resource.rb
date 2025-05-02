class TestBinaryResource < ModelContextProtocol::Server::Resource
  with_metadata do
    name "Project Logo"
    description "The logo for the project"
    mime_type "image/jpeg"
    uri "resource://project-logo"
  end

  def call
    # In a real implementation, we would retrieve the binary resource
    # This is a small valid base64 encoded string (represents "test")
    data = "dGVzdA=="
    respond_with :binary, blob: data
  end
end
