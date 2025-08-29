class TestResourceTemplate < ModelContextProtocol::Server::ResourceTemplate
  Completion = ModelContextProtocol::Server::Completion.define do
    hints = {
      "name" => ["top-secret-plans.txt"]
    }
    values = hints[argument_name].grep(/#{argument_value}/)

    respond_with values:
  end

  with_metadata do
    name "project-document-resource-template"
    description "A resource template for retrieving project documents"
    mime_type "text/plain"
    uri_template "file:///{name}" do
      completion :name, Completion
    end
  end
end
