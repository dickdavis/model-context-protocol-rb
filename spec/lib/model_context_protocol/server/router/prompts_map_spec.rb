RSpec.describe ModelContextProtocol::Server::Router::PromptsMap do
  subject(:prompts_map) { described_class.new(routes) }

  let(:routes) { {} }
  let(:handler) { -> { "handler" } }

  describe "#list" do
    it "registers a prompts/list route" do
      prompts_map.list(handler, broadcast_changes: true)

      expect(routes["prompts/list"]).to eq(
        handler: handler,
        options: {broadcast_changes: true}
      )
    end

    it "defaults broadcast_changes to false" do
      prompts_map.list(handler)

      expect(routes["prompts/list"]).to eq(
        handler: handler,
        options: {broadcast_changes: false}
      )
    end
  end

  describe "#get" do
    it "registers a prompts/get route" do
      prompts_map.get(handler)

      expect(routes["prompts/get"]).to eq(
        handler: handler,
        options: {}
      )
    end
  end
end
