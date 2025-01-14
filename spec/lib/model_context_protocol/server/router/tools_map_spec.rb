RSpec.describe ModelContextProtocol::Server::Router::ToolsMap do
  subject(:tools_map) { described_class.new(routes) }

  let(:routes) { {} }
  let(:handler) { -> { "handler" } }

  describe "#list" do
    it "registers a tools/list route" do
      tools_map.list(handler, broadcast_changes: true)

      expect(routes["tools/list"]).to eq(
        handler: handler,
        options: {broadcast_changes: true}
      )
    end

    it "defaults broadcast_changes to false" do
      tools_map.list(handler)

      expect(routes["tools/list"]).to eq(
        handler: handler,
        options: {broadcast_changes: false}
      )
    end
  end

  describe "#call" do
    it "registers a tools/call route" do
      tools_map.call(handler)

      expect(routes["tools/call"]).to eq(
        handler: handler,
        options: {}
      )
    end
  end
end
