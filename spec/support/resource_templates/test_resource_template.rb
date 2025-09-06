class TestResourceTemplate < ModelContextProtocol::Server::ResourceTemplate
  define do
    name "project-document-resource-template"
    description "A resource template for retrieving project documents"
    mime_type "text/plain"
    uri_template "file:///{name}" do
      completion :name, ["top-secret-plans.txt"]
    end
  end

  # You can optionally define a custom completion for an argument and pass it to completions.
  # Completion = ModelContextProtocol::Server::Completion.define do
  #   hints = {
  #     "name" => ["top-secret-plans.txt"]
  #   }
  #   values = hints[argument_name].grep(/#{argument_value}/)

  #   respond_with values:
  # end

  # define do
  #   name "project-document-resource-template"
  #   description "A resource template for retrieving project documents"
  #   mime_type "text/plain"
  #   uri_template "file:///{name}" do
  #     completion :name, Completion
  #   end
  # end
end
