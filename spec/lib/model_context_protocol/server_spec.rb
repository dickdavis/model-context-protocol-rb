require "spec_helper"

RSpec.describe ModelContextProtocol::Server do
  subject(:server) do
    ModelContextProtocol::Server.new do |config|
      config.name = "MCP Development Server"
      config.version = "1.0.0"
      config.router = ModelContextProtocol::Server::Router.new
    end
  end

  describe "start" do
    subject(:start) { server.start }

    context "prompt requests" do
      it "handles valid requests" do
      end

      it "handles invalid requests" do
      end

      it "handles unexpected errors" do
      end
    end

    context "resource requests" do
      it "handles valid requests" do
      end

      it "handles invalid requests" do
      end

      it "handles unexpected errors" do
      end
    end

    context "tool requests" do
      it "handles valid requests" do
      end

      it "handles invalid requests" do
      end

      it "handles unexpected errors" do
      end
    end
  end
end
