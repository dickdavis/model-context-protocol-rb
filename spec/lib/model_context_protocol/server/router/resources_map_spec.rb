RSpec.describe ModelContextProtocol::Server::Router::ResourcesMap do
  subject(:resources_map) { described_class.new(routes) }

  let(:routes) { {} }
  let(:handler) { -> { "handler" } }

  describe "#list" do
    it "registers a resources/list route" do
      resources_map.list(handler, broadcast_changes: true)

      expect(routes["resources/list"]).to eq(
        handler: handler,
        options: {broadcast_changes: true}
      )
    end

    it "defaults broadcast_changes to false" do
      resources_map.list(handler)

      expect(routes["resources/list"]).to eq(
        handler: handler,
        options: {broadcast_changes: false}
      )
    end
  end

  describe "#read" do
    it "registers a resources/read route" do
      resources_map.read(handler, allow_subscriptions: true)

      expect(routes["resources/read"]).to eq(
        handler: handler,
        options: {allow_subscriptions: true}
      )
    end

    it "defaults allow_subscriptions to false" do
      resources_map.read(handler)

      expect(routes["resources/read"]).to eq(
        handler: handler,
        options: {allow_subscriptions: false}
      )
    end
  end
end
