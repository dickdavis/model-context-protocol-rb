class TestBinaryResource < ModelContextProtocol::Server::Resource
  with_metadata do
    {
      name: "Test Binary Resource",
      description: "A test binary resource",
      mime_type: "image/jpeg",
      uri: "resource://test-resource"
    }
  end

  def call
    BinaryResponse[resource: self, blob: "base64data"]
  end
end
