class TestOldStyleCompletionResourceTemplate < ModelContextProtocol::Server::ResourceTemplate
  StatusCompletion = ModelContextProtocol::Server::Completion.define do
    statuses = ["active", "inactive", "pending", "archived"]
    values = statuses.grep(/#{argument_value}/)
    respond_with values:
  end

  TypeCompletion = ModelContextProtocol::Server::Completion.define do
    types = {
      "type" => ["document", "image", "video", "audio"]
    }
    values = types[argument_name].grep(/#{argument_value}/)
    respond_with values:
  end

  with_metadata do
    name "test-old-style-completion-resource-template"
    description "A resource template to test old-style completion classes"
    mime_type "application/json"
    uri_template "api:///{status}/{type}" do
      completion :status, StatusCompletion
      completion :type, TypeCompletion
    end
  end
end
