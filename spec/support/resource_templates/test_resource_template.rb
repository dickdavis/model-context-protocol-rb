class TestResourceTemplate < ModelContextProtocol::Server::ResourceTemplate
  with_metadata do
    name "Test Resource Template"
    description "A test resource template"
    mime_type "text/plain"
    uri_template "resource://{name}"
  end

  def call
    result = "Here's the resource name you requested: #{extracted_uri["name"]}"
    respond_with :text, text: result
  end
end
