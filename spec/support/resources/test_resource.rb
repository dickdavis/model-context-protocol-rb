class TestResource < ModelContextProtocol::Server::Resource
  with_metadata do
    name "top-secret-plans.txt"
    description "Top secret plans to do top secret things"
    mime_type "text/plain"
    uri "file:///top-secret-plans.txt"
  end

  def call
    unless authorized?(context[:user_id])
      logger.info("This fool thinks he can get my top secret plans...")
      return respond_with :text, text: "Nothing to see here, move along."
    end

    respond_with :text, text: "I'm finna eat all my wife's leftovers."
  end

  private

  def authorized?(user_id)
    authorized_users = ["42", "123456"]
    authorized_users.any?(user_id)
  end
end
