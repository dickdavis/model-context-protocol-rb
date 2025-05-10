class TestResource < ModelContextProtocol::Server::Resource
  with_metadata do
    name "Test Resource"
    description "A test resource"
    mime_type "text/plain"
    uri "resource:///test-resource"
  end

  def call
    respond_with :text, text: "Here's the data"
  end
end
