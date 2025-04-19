require "spec_helper"

RSpec.describe ModelContextProtocol::Server::Completion do
  describe ".call" do
    let(:argument_name) { "message" }
    let(:argument_value) { "f" }

    it "instantiates the tool with the provided parameters" do
      expect(TestCompletion).to receive(:new).with(argument_name, argument_value).and_call_original
      TestCompletion.call(argument_name, argument_value)
    end

    it "returns the response from the instance's call method" do
      response = TestCompletion.call(argument_name, argument_value)
      aggregate_failures do
        expect(response.values).to eq(["foo"])
        expect(response.total).to eq(1)
        expect(response.hasMore).to be_falsey
        expect(response.serialized).to eq(
          completion: {
            values: ["foo"],
            total: 1,
            hasMore: false
          }
        )
      end
    end
  end
end
