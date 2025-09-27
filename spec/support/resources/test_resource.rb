class TestResource < ModelContextProtocol::Server::Resource
  define do
    name "top-secret-plans.txt"
    title "Top Secret Plans"
    description "Top secret plans to do top secret things"
    mime_type "text/plain"
    uri "file:///top-secret-plans.txt"
  end

  def call
    client_logger.info("Accessing top secret plans")

    # Server logging for debugging and monitoring (not sent to client)
    server_logger.debug("Resource access requested")
    server_logger.info("Serving top secret plans content")

    user_id = context[:user_id]

    if user_id
      client_logger.info("User #{user_id} is accessing secret plans")
      server_logger.info("User #{user_id} accessed secret plans resource")
    end

    respond_with text: "I'm finna eat all my wife's leftovers."
  end
end
