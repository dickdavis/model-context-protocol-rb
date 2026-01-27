# frozen_string_literal: true

require "spec_helper"

RSpec.describe "List Changed Notifications" do
  let(:redis) { MockRedis.new }
  let(:session_store) do
    ModelContextProtocol::Server::StreamableHttpTransport::SessionStore.new(redis, ttl: 300)
  end
  let(:session_id) { SecureRandom.uuid }

  before do
    redis.flushdb
  end

  describe "handler change detection" do
    let(:initial_prompts) { ["prompt1", "prompt2"] }
    let(:initial_resources) { ["resource1"] }
    let(:initial_tools) { ["tool1", "tool2"] }

    before do
      session_store.create_session(session_id, {server_instance: "test-server"})
      session_store.store_registered_handlers(
        session_id,
        prompts: initial_prompts,
        resources: initial_resources,
        tools: initial_tools
      )
    end

    context "when handlers have not changed" do
      it "returns matching handlers from storage" do
        stored = session_store.get_registered_handlers(session_id)

        aggregate_failures do
          expect(stored[:prompts].sort).to eq(initial_prompts.sort)
          expect(stored[:resources].sort).to eq(initial_resources.sort)
          expect(stored[:tools].sort).to eq(initial_tools.sort)
        end
      end
    end

    context "when tools have been added" do
      it "detects the change" do
        stored = session_store.get_registered_handlers(session_id)
        current_tools = ["tool1", "tool2", "tool3"]

        expect(current_tools.sort).not_to eq(stored[:tools].sort)
      end
    end

    context "when prompts have been removed" do
      it "detects the change" do
        stored = session_store.get_registered_handlers(session_id)
        current_prompts = ["prompt1"]

        expect(current_prompts.sort).not_to eq(stored[:prompts].sort)
      end
    end

    context "when handlers are reordered but not changed" do
      it "does not detect a change when sorted" do
        stored = session_store.get_registered_handlers(session_id)
        current_prompts = ["prompt2", "prompt1"]

        expect(current_prompts.sort).to eq(stored[:prompts].sort)
      end
    end
  end

  describe "handler storage lifecycle" do
    it "handles complete session lifecycle with handler updates" do
      # Create session
      session_store.create_session(session_id, {server_instance: "test-server"})

      # Initially no handlers stored
      expect(session_store.get_registered_handlers(session_id)).to be_nil

      # Store initial handlers
      session_store.store_registered_handlers(
        session_id,
        prompts: ["prompt1"],
        resources: [],
        tools: ["tool1"]
      )

      stored = session_store.get_registered_handlers(session_id)
      aggregate_failures do
        expect(stored[:prompts]).to eq(["prompt1"])
        expect(stored[:resources]).to eq([])
        expect(stored[:tools]).to eq(["tool1"])
      end

      # Update handlers (simulating a change)
      session_store.store_registered_handlers(
        session_id,
        prompts: ["prompt1", "prompt2"],
        resources: ["resource1"],
        tools: ["tool1"]
      )

      updated = session_store.get_registered_handlers(session_id)
      aggregate_failures do
        expect(updated[:prompts]).to eq(["prompt1", "prompt2"])
        expect(updated[:resources]).to eq(["resource1"])
        expect(updated[:tools]).to eq(["tool1"])
      end

      # Cleanup session
      session_store.cleanup_session(session_id)
      expect(session_store.get_registered_handlers(session_id)).to be_nil
    end

    it "stores handlers independently per session" do
      session_id_1 = SecureRandom.uuid
      session_id_2 = SecureRandom.uuid

      session_store.create_session(session_id_1, {server_instance: "server-1"})
      session_store.create_session(session_id_2, {server_instance: "server-2"})

      session_store.store_registered_handlers(
        session_id_1,
        prompts: ["prompt_a"],
        resources: [],
        tools: ["tool_x"]
      )

      session_store.store_registered_handlers(
        session_id_2,
        prompts: ["prompt_b", "prompt_c"],
        resources: ["resource_y"],
        tools: []
      )

      handlers_1 = session_store.get_registered_handlers(session_id_1)
      handlers_2 = session_store.get_registered_handlers(session_id_2)

      aggregate_failures do
        expect(handlers_1[:prompts]).to eq(["prompt_a"])
        expect(handlers_1[:tools]).to eq(["tool_x"])

        expect(handlers_2[:prompts]).to eq(["prompt_b", "prompt_c"])
        expect(handlers_2[:resources]).to eq(["resource_y"])
        expect(handlers_2[:tools]).to eq([])
      end
    end
  end

  describe "Registry#handler_names" do
    it "returns current handler names from registry" do
      registry = ModelContextProtocol::Server::Registry.new do
        prompts do
          register TestPrompt
        end

        resources do
          register TestResource
        end

        tools do
          register TestToolWithTextResponse
        end
      end

      names = registry.handler_names

      aggregate_failures do
        expect(names[:prompts]).to include("brainstorm_excuses")
        expect(names[:resources]).to include("top-secret-plans.txt")
        expect(names[:tools]).to include("double")
      end
    end
  end

  describe "StreamableHttpTransport list changed integration" do
    let(:mock_redis) { MockRedis.new }

    before(:all) do
      ModelContextProtocol::Server.configure_redis do |config|
        config.redis_url = "redis://localhost:6379/15"
      end

      ModelContextProtocol::Server.configure_server_logging do |config|
        config.logdev = File::NULL
        config.level = Logger::FATAL
      end
    end

    before(:each) do
      # Mock the pool.with method to use mock_redis
      allow(ModelContextProtocol::Server::RedisConfig.pool).to receive(:with).and_yield(mock_redis)
      allow(ModelContextProtocol::Server::RedisConfig.pool).to receive(:checkout).and_return(mock_redis)
      allow(ModelContextProtocol::Server::RedisConfig.pool).to receive(:checkin)
      mock_redis.flushdb
    end

    def build_rack_env(method: "POST", body: "", headers: {})
      env = {
        "REQUEST_METHOD" => method,
        "PATH_INFO" => "/mcp",
        "rack.input" => StringIO.new(body),
        "CONTENT_TYPE" => "application/json",
        "HTTP_ACCEPT" => "application/json"
      }

      headers.each do |key, value|
        env["HTTP_#{key.upcase.tr("-", "_")}"] = value
      end

      env
    end

    def setup_transport_mocks
      monitor_thread = double("monitor_thread", alive?: false, kill: nil, join: nil, name: nil)
      poller_thread = double("poller_thread", alive?: false, kill: nil, join: nil, name: nil)
      allow(poller_thread).to receive(:name=)
      allow(Thread).to receive(:new).with(no_args).and_return(monitor_thread, poller_thread)
    end

    describe "#check_and_notify_handler_changes" do
      let(:registry) do
        ModelContextProtocol::Server::Registry.new do
          tools list_changed: true do
            register TestToolWithTextResponse
          end
        end
      end

      let(:server) do
        reg = registry
        ModelContextProtocol::Server.new do |config|
          config.name = "test-server"
          config.version = "1.0.0"
          config.registry = reg
          config.transport = {
            type: :streamable_http,
            require_sessions: true,
            validate_origin: false,
            env: build_rack_env
          }
        end
      end

      let(:transport) do
        setup_transport_mocks
        server.start
        server.transport
      end

      it "returns early when session_id is nil" do
        expect(transport).not_to receive(:send_notification)
        transport.send(:check_and_notify_handler_changes, nil)
      end

      it "returns early when session does not exist" do
        expect(transport).not_to receive(:send_notification)
        transport.send(:check_and_notify_handler_changes, "nonexistent-session")
      end

      it "returns early when no previous handlers stored (first request after init)" do
        session_store = transport.instance_variable_get(:@session_store)
        session_store.create_session(session_id, {server_instance: "test"})

        expect(transport).not_to receive(:send_notification)
        transport.send(:check_and_notify_handler_changes, session_id)
      end

      it "does not send notification when handlers have not changed" do
        session_store = transport.instance_variable_get(:@session_store)
        session_store.create_session(session_id, {server_instance: "test"})
        session_store.store_registered_handlers(
          session_id,
          prompts: [],
          resources: [],
          tools: ["double"]
        )

        expect(transport).not_to receive(:send_notification)
        transport.send(:check_and_notify_handler_changes, session_id)
      end

      it "sends notification when tools have changed" do
        session_store = transport.instance_variable_get(:@session_store)
        session_store.create_session(session_id, {server_instance: "test"})
        session_store.store_registered_handlers(
          session_id,
          prompts: [],
          resources: [],
          tools: ["old_tool"]
        )

        expect(transport).to receive(:send_notification).with(
          "notifications/tools/list_changed",
          {},
          session_id: session_id
        )
        transport.send(:check_and_notify_handler_changes, session_id)
      end

      it "updates stored handlers after sending notification" do
        session_store = transport.instance_variable_get(:@session_store)
        session_store.create_session(session_id, {server_instance: "test"})
        session_store.store_registered_handlers(
          session_id,
          prompts: [],
          resources: [],
          tools: ["old_tool"]
        )

        allow(transport).to receive(:send_notification)
        transport.send(:check_and_notify_handler_changes, session_id)

        updated = session_store.get_registered_handlers(session_id)
        expect(updated[:tools]).to eq(["double"])
      end

      it "does not send notification when list_changed is not enabled for the type" do
        # Create a registry without list_changed enabled for tools
        registry_no_list_changed = ModelContextProtocol::Server::Registry.new do
          tools do
            register TestToolWithTextResponse
          end
        end

        server_no_list_changed = ModelContextProtocol::Server.new do |config|
          config.name = "test-server"
          config.version = "1.0.0"
          config.registry = registry_no_list_changed
          config.transport = {
            type: :streamable_http,
            require_sessions: true,
            validate_origin: false,
            env: build_rack_env
          }
        end

        setup_transport_mocks
        server_no_list_changed.start
        transport_no_list_changed = server_no_list_changed.transport

        session_store = transport_no_list_changed.instance_variable_get(:@session_store)
        session_store.create_session(session_id, {server_instance: "test"})
        session_store.store_registered_handlers(
          session_id,
          prompts: [],
          resources: [],
          tools: ["old_tool"]
        )

        expect(transport_no_list_changed).not_to receive(:send_notification)
        transport_no_list_changed.send(:check_and_notify_handler_changes, session_id)
      end

      it "handles errors gracefully without raising" do
        session_store = transport.instance_variable_get(:@session_store)
        session_store.create_session(session_id, {server_instance: "test"})
        session_store.store_registered_handlers(
          session_id,
          prompts: [],
          resources: [],
          tools: ["old_tool"]
        )

        # Force an error by making send_notification raise
        allow(transport).to receive(:send_notification).and_raise(StandardError, "Test error")

        expect { transport.send(:check_and_notify_handler_changes, session_id) }.not_to raise_error
      end
    end

    describe "#list_changed_enabled?" do
      let(:registry) do
        ModelContextProtocol::Server::Registry.new do
          prompts list_changed: true do
            register TestPrompt
          end

          resources list_changed: false do
            register TestResource
          end

          tools do
            register TestToolWithTextResponse
          end
        end
      end

      let(:server) do
        reg = registry
        ModelContextProtocol::Server.new do |config|
          config.name = "test-server"
          config.version = "1.0.0"
          config.registry = reg
          config.transport = {
            type: :streamable_http,
            require_sessions: false,
            validate_origin: false,
            env: build_rack_env
          }
        end
      end

      let(:transport) do
        setup_transport_mocks
        server.start
        server.transport
      end

      it "returns true when list_changed is enabled for prompts" do
        expect(transport.send(:list_changed_enabled?, :prompts)).to be true
      end

      it "returns false when list_changed is explicitly false for resources" do
        expect(transport.send(:list_changed_enabled?, :resources)).to be false
      end

      it "returns false when list_changed is not configured for tools" do
        expect(transport.send(:list_changed_enabled?, :tools)).to be false
      end
    end

    describe "initialization stores handlers" do
      let(:registry) do
        ModelContextProtocol::Server::Registry.new do
          tools list_changed: true do
            register TestToolWithTextResponse
          end
        end
      end

      let(:server) do
        reg = registry
        ModelContextProtocol::Server.new do |config|
          config.name = "test-server"
          config.version = "1.0.0"
          config.registry = reg
          config.transport = {
            type: :streamable_http,
            require_sessions: true,
            validate_origin: false,
            env: build_rack_env(
              body: {"method" => "initialize", "id" => "init-1", "params" => {}}.to_json,
              headers: {"Accept" => "application/json"}
            )
          }
        end
      end

      it "stores initial handlers when session is created" do
        setup_transport_mocks
        # server.start calls transport.handle and returns the result
        result = server.start
        transport = server.transport

        # Extract session_id from response headers
        new_session_id = result[:headers]["Mcp-Session-Id"]
        expect(new_session_id).not_to be_nil

        # Verify handlers were stored
        session_store = transport.instance_variable_get(:@session_store)
        handlers = session_store.get_registered_handlers(new_session_id)

        aggregate_failures do
          expect(handlers).not_to be_nil
          expect(handlers[:tools]).to eq(["double"])
          expect(handlers[:prompts]).to eq([])
          expect(handlers[:resources]).to eq([])
        end
      end
    end
  end
end
