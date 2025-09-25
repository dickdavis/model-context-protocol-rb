require "spec_helper"

RSpec.describe ModelContextProtocol::Server::Instrumentation do
  describe "module structure" do
    it "defines Event data object" do
      expect(described_class::Event).to be_a(Class)
    end

    it "defines Registry class" do
      expect(described_class::Registry).to be_a(Class)
    end

    it "defines BaseCollector class" do
      expect(described_class::BaseCollector).to be_a(Class)
    end

    it "defines TimingCollector class" do
      expect(described_class::TimingCollector).to be_a(Class)
    end

    it "defines RedisCollector class" do
      expect(described_class::RedisCollector).to be_a(Class)
    end
  end

  describe "collector inheritance" do
    it "TimingCollector inherits from BaseCollector" do
      expect(described_class::TimingCollector).to be < described_class::BaseCollector
    end

    it "RedisCollector inherits from BaseCollector" do
      expect(described_class::RedisCollector).to be < described_class::BaseCollector
    end
  end
end
