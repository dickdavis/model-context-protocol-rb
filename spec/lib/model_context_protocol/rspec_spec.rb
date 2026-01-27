require "spec_helper"
require "model_context_protocol/rspec"

RSpec.describe ModelContextProtocol::RSpec do
  describe ".configure!" do
    it "is defined" do
      expect(described_class).to respond_to(:configure!)
    end
  end
end
