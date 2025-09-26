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
    user_id = context[:user_id]

    if user_id
      client_logger.info("User #{user_id} is accessing secret plans")
    end

    respond_with text: "I'm finna eat all my wife's leftovers."
  end
end
