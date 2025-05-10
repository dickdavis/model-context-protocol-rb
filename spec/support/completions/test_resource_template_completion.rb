class TestResourceTemplateCompletion < ModelContextProtocol::Server::Completion
  def call
    hints = {
      "name" => ["test-resource", "project-logo"]
    }
    values = hints[argument_name].grep(/#{argument_value}/)

    respond_with values:
  end
end
