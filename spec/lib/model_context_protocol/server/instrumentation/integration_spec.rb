require "spec_helper"

RSpec.describe "ModelContextProtocol Server Instrumentation Integration" do
  describe "complete instrumentation flow" do
    let(:configuration) do
      ModelContextProtocol::Server::Configuration.new.tap do |config|
        config.name = "test-server"
        config.version = "1.0.0"
        config.registry = ModelContextProtocol::Server::Registry.new

        # Enable timing instrumentation
        config.enable_instrumentation(collectors: [:timing])
      end
    end

    let(:router) { ModelContextProtocol::Server::Router.new(configuration: configuration) }
    let(:events) { [] }

    before do
      # Set up a test handler
      router.map("test/method") do |message|
        # Simulate some work
        sleep(0.001)
        {result: "success", params: message["params"]}
      end

      # Set up instrumentation callback
      configuration.instrumentation_registry.add_callback do |event|
        events << event
      end
    end

    it "instruments request execution and captures timing metrics" do
      message = {
        "method" => "test/method",
        "id" => "req-123",
        "params" => {"key" => "value"}
      }

      result = router.route(message)

      expect(result).to be_a(Hash)
      expect(result[:result]).to eq("success")

      # Check that instrumentation event was captured
      expect(events.size).to eq(1)
      event = events.first

      expect(event.method).to eq("test/method")
      expect(event.request_id).to eq("req-123")
      expect(event.metrics[:duration_ms]).to be >= 1.0 # Should be at least 1ms due to sleep
      expect(event.metrics[:cpu_time_ms]).to be_a(Float)

      # Test serialization
      serialized = event.serialized
      expect(serialized).to include(
        method: "test/method",
        request_id: "req-123",
        metrics: include(
          duration_ms: be_a(Float),
          cpu_time_ms: be_a(Float)
        )
      )
    end

    it "captures errors in instrumentation" do
      router.map("test/error") do |message|
        raise StandardError, "Test error"
      end

      message = {
        "method" => "test/error",
        "id" => "req-error",
        "params" => {}
      }

      expect do
        router.route(message)
      end.to raise_error(StandardError, "Test error")

      # Check that instrumentation event was captured with error
      expect(events.size).to eq(1)
      event = events.first

      expect(event.method).to eq("test/error")
      expect(event.request_id).to eq("req-error")
      # Error handling removed from Event - errors should be handled elsewhere
    end

    it "works with global instrumentation" do
      global_events = []

      # Set up global instrumentation
      ModelContextProtocol::Server.instrument do |event|
        global_events << event
      end

      message = {
        "method" => "test/method",
        "id" => "req-global",
        "params" => {"global" => true}
      }

      router.route(message)

      # Both configuration-level and global instrumentation should fire
      expect(events.size).to eq(1) # Configuration-level
      expect(global_events.size).to eq(1) # Global-level

      # Verify both captured the same method
      expect(events.first.method).to eq("test/method")
      expect(global_events.first.method).to eq("test/method")
      expect(events.first.request_id).to eq("req-global")
      expect(global_events.first.request_id).to eq("req-global")
    end
  end

  describe "custom collector integration" do
    it "supports custom collectors" do
      configuration = ModelContextProtocol::Server::Configuration.new.tap do |config|
        config.name = "test-server"
        config.version = "1.0.0"
        config.registry = ModelContextProtocol::Server::Registry.new
        config.enable_instrumentation(collectors: [:timing, TestCustomCollector.new])
      end

      router = ModelContextProtocol::Server::Router.new(configuration: configuration)
      events = []

      router.map("test/custom") { |msg| "custom result" }

      configuration.instrumentation_registry.add_callback do |event|
        events << event
      end

      message = {
        "method" => "test/custom",
        "id" => "req-custom",
        "params" => {}
      }

      router.route(message)

      expect(events.size).to eq(1)
      event = events.first

      expect(event.metrics[:custom_metric]).to eq("started_finished")
      expect(event.metrics[:custom_value]).to eq(42)
      expect(event.metrics[:cpu_time_ms]).to be_a(Float) # From timing collector
    end
  end
end
