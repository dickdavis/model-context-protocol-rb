RSpec.shared_context "with managed mcp lifecycle" do
  around do |example|
    ModelContextProtocol::Server.start
    example.run
    ModelContextProtocol::Server.shutdown
  end
end
