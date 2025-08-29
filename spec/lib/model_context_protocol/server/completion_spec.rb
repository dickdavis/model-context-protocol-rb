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

  describe ".define" do
    let(:argument_name) { "name" }
    let(:argument_value) { "f" }

    it "creates a new completion class with the given block as the call method" do
      completion_class = ModelContextProtocol::Server::Completion.define do
        hints = {
          "name" => ["foo", "bar", "foobar"]
        }
        values = hints[argument_name].grep(/#{argument_value}/)
        respond_with values:
      end

      response = completion_class.call(argument_name, argument_value)
      aggregate_failures do
        expect(response.values).to eq(["foo", "foobar"])
        expect(response.total).to eq(2)
        expect(response.hasMore).to be_falsey
      end
    end

    it "creates a class that inherits from Completion" do
      completion_class = ModelContextProtocol::Server::Completion.define do
        respond_with values: []
      end

      expect(completion_class.new("test", "test")).to be_a(ModelContextProtocol::Server::Completion)
    end

    it "has access to argument_name and argument_value" do
      completion_class = ModelContextProtocol::Server::Completion.define do
        respond_with values: [argument_name, argument_value]
      end

      response = completion_class.call("test_arg", "test_val")
      expect(response.values).to eq(["test_arg", "test_val"])
    end
  end
end
