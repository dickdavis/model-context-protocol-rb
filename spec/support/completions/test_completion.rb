class TestCompletion < ModelContextProtocol::Server::Completion
  def call
    hints = {
      "message" => ["hello", "world", "foo", "bar"]
    }
    values = hints[argument_name].grep(/#{argument_value}/)

    respond_with values:
  end
end
