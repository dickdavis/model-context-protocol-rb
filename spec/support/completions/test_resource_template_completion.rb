class TestResourceTemplateCompletion < ModelContextProtocol::Server::Completion
  def call
    hints = {
      "name" => ["top-secret-plans.txt", "project-logo.png"]
    }
    values = hints[argument_name].grep(/#{argument_value}/)

    respond_with values:
  end
end
