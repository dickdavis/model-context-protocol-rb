RSpec.shared_context "with managed mcp lifecycle" do
  around do |example|
    ModelContextProtocol::Server.configure_server_logging do |config|
      config.logdev = File::NULL
    end
    ModelContextProtocol::Server.start
    example.run
    ModelContextProtocol::Server.shutdown
    ModelContextProtocol::Server::GlobalConfig::ServerLogging.reset!
  end
end
