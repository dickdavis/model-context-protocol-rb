RSpec.describe ModelContextProtocol::Server::Router do
  subject(:server) do
    config = ModelContextProtocol::Server::Configuration.new
    config.name = "test_server"
    config.version = "1.0.0"
    double("Server", configuration: config)
  end

  describe "protocol routes" do
    subject(:router) do
      router = described_class.new
      router.server = server
      router
    end

    describe "initialize handler" do
      let(:message) { {"method" => "initialize"} }

      it "returns protocol information" do
        result = router.route(message)

        expect(result).to include(
          protocolVersion: "2024-11-05",
          serverInfo: {
            name: "test_server",
            version: "1.0.0"
          }
        )
      end

      context "when no routes are configured" do
        it "returns empty capabilities" do
          result = router.route(message)
          expect(result[:capabilities]).to be_empty
        end
      end
    end

    describe "notifications/initialized handler" do
      let(:message) { {"method" => "notifications/initialized"} }

      it "returns nil" do
        expect(router.route(message)).to be_nil
      end
    end

    describe "ping handler" do
      let(:message) { {"method" => "ping"} }

      it "returns empty hash" do
        expect(router.route(message)).to eq({})
      end
    end
  end

  describe "capability detection" do
    subject(:router) do
      router = described_class.new do
        prompts do
          list Class.new {
            def self.call(*)
            end
          }, broadcast_changes: true
          get Class.new {
            def self.call(*)
            end
          }
        end

        resources do
          list Class.new {
            def self.call(*)
            end
          }, broadcast_changes: true
          read Class.new {
            def self.call(*)
            end
          }, allow_subscriptions: true
        end

        tools do
          list Class.new {
            def self.call(*)
            end
          }, broadcast_changes: true
          call Class.new {
            def self.call(*)
            end
          }
        end
      end
      router.server = server
      router
    end

    let(:message) { {"method" => "initialize"} }

    it "detects prompt capabilities" do
      result = router.route(message)
      expect(result[:capabilities][:prompts]).to eq(broadcast_changes: true)
    end

    it "detects resource capabilities" do
      result = router.route(message)
      expect(result[:capabilities][:resources]).to eq(
        broadcast_changes: true,
        subscribe: true
      )
    end

    it "detects tool capabilities" do
      result = router.route(message)
      expect(result[:capabilities][:tools]).to eq(broadcast_changes: true)
    end
  end

  describe "user-defined routes" do
    let(:prompt_list) { spy("prompt_list") }
    let(:prompt_get) { spy("prompt_get") }
    let(:resource_list) { spy("resource_list") }
    let(:resource_read) { spy("resource_read") }
    let(:tool_list) { spy("tool_list") }
    let(:tool_call) { spy("tool_call") }

    subject(:router) do
      pl = prompt_list
      pg = prompt_get
      rl = resource_list
      rr = resource_read
      tl = tool_list
      tc = tool_call

      described_class.new do
        prompts do
          list pl
          get pg
        end

        resources do
          list rl
          read rr
        end

        tools do
          list tl
          call tc
        end
      end
    end

    it "routes prompts/list" do
      message = {"method" => "prompts/list"}
      router.route(message)
      expect(prompt_list).to have_received(:call).with(message)
    end

    it "routes prompts/get" do
      message = {"method" => "prompts/get"}
      router.route(message)
      expect(prompt_get).to have_received(:call).with(message)
    end

    it "routes resources/list" do
      message = {"method" => "resources/list"}
      router.route(message)
      expect(resource_list).to have_received(:call).with(message)
    end

    it "routes resources/read" do
      message = {"method" => "resources/read"}
      router.route(message)
      expect(resource_read).to have_received(:call).with(message)
    end

    it "routes tools/list" do
      message = {"method" => "tools/list"}
      router.route(message)
      expect(tool_list).to have_received(:call).with(message)
    end

    it "routes tools/call" do
      message = {"method" => "tools/call"}
      router.route(message)
      expect(tool_call).to have_received(:call).with(message)
    end

    it "returns nil for unknown routes" do
      message = {"method" => "unknown/route"}
      expect(router.route(message)).to be_nil
    end
  end
end
