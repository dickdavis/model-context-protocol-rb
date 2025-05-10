class TestResourceTemplate < ModelContextProtocol::Server::ResourceTemplate
  with_metadata do
    name "Test Resource Template"
    description "A test resource template"
    mime_type "text/plain"
    uri_template "resource:///{name}" do
      completion :name, TestResourceTemplateCompletion
    end
  end
end
