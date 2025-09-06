class TestResource < ModelContextProtocol::Server::Resource
  define do
    name "top-secret-plans.txt"
    title "Top Secret Plans"
    description "Top secret plans to do top secret things"
    mime_type "text/plain"
    uri "file:///top-secret-plans.txt"
  end

  def call
    respond_with text: "I'm finna eat all my wife's leftovers."
  end
end
