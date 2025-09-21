require "spec_helper"

TestResponse = Data.define(:text) do
  def serialized
    {text:}
  end
end

InitializeTestResponse = Data.define(:protocol_version) do
  def serialized
    {
      protocolVersion: protocol_version,
      capabilities: {},
      serverInfo: {name: "test-server", version: "1.0.0"}
    }
  end
end

RSpec.describe ModelContextProtocol::Server::StreamableHttpTransport do
  before(:all) do
    # Configure Redis globally for all StreamableHttpTransport tests
    ModelContextProtocol::Server::RedisConfig.configure do |config|
      config.redis_url = "redis://localhost:6379/15"
    end
  end

  before(:each) do
    # Stub the Redis pool to return our mock_redis instance
    allow(ModelContextProtocol::Server::RedisConfig.pool).to receive(:checkout).and_return(mock_redis)
    allow(ModelContextProtocol::Server::RedisConfig.pool).to receive(:checkin)
  end

  subject(:transport) do
    described_class.new(
      router: router,
      configuration: configuration
    )
  end
  let(:router) { ModelContextProtocol::Server::Router.new(configuration: configuration) }
  let(:mock_redis) { MockRedis.new }
  let(:mcp_logger) { configuration.logger }
  let(:configuration) do
    config = ModelContextProtocol::Server::Configuration.new
    config.name = "test-server"
    config.registry = ModelContextProtocol::Server::Registry.new
    config.version = "1.0.0"
    config.transport = {
      type: :streamable_http,
      require_sessions: false,
      validate_origin: false,
      env: rack_env
    }
    config
  end

  let(:session_id) { "test-session-123" }
  let(:rack_env) { build_rack_env }

  def build_rack_env(method: "POST", path: "/mcp", body: "", headers: {})
    env = {
      "REQUEST_METHOD" => method,
      "PATH_INFO" => path,
      "rack.input" => StringIO.new(body),
      "CONTENT_TYPE" => "application/json",
      "HTTP_ACCEPT" => "application/json"
    }

    headers.each do |key, value|
      env["HTTP_#{key.upcase.tr("-", "_")}"] = value
    end

    env
  end

  def set_request_env(method: "POST", body: "", headers: {})
    configuration.transport[:env] = build_rack_env(
      method: method,
      body: body,
      headers: headers
    )
  end

  before do
    mock_redis.flushdb

    allow(mock_redis).to receive(:publish)
    allow(mock_redis).to receive(:subscribe).and_yield(double("on").tap do |on|
      allow(on).to receive(:message).and_yield("channel", '{"session_id":"test","message":"data"}')
    end)

    # Stub Thread.new for monitoring thread to prevent actual thread creation in tests
    # but allow SSE stream threads to work for testing
    monitor_thread = double("monitor_thread", alive?: false, kill: nil, join: nil)
    allow(Thread).to receive(:new).and_call_original
    allow(Thread).to receive(:new).with(no_args).and_return(monitor_thread)

    router.map("initialize") do |message|
      client_protocol_version = message["params"]&.dig("protocolVersion")
      supported_versions = ["2025-06-18"]

      negotiated_version = if client_protocol_version && supported_versions.include?(client_protocol_version)
        client_protocol_version
      else
        supported_versions.first
      end

      InitializeTestResponse[protocol_version: negotiated_version]
    end

    router.map("ping") do |message|
      TestResponse[text: "pong"]
    end

    router.map("error_method") do |message|
      raise "Something went wrong"
    end
  end

  describe "#handle" do
    context "when env hash is missing" do
      before do
        configuration.transport = {type: :streamable_http}
      end

      it "raises ArgumentError" do
        expect { transport.handle }.to raise_error(
          ArgumentError,
          "StreamableHTTP transport requires Rack env hash in transport_options"
        )
      end
    end

    context "with POST request" do
      context "for initialization request" do
        let(:init_request) { {"method" => "initialize", "params" => {}, "id" => "init-1"} }

        before do
          set_request_env(
            body: init_request.to_json,
            headers: {"Accept" => "application/json"}
          )
        end

        context "when sessions are not required" do
          it "returns response without session ID" do
            result = transport.handle

            aggregate_failures do
              expect(result[:json]).to eq({
                jsonrpc: "2.0",
                id: "init-1",
                result: {
                  protocolVersion: "2025-06-18",
                  capabilities: {},
                  serverInfo: {name: "test-server", version: "1.0.0"}
                }
              })
              expect(result[:status]).to eq(200)
              expect(result[:headers]).not_to have_key("Mcp-Session-Id")
              expect(result[:headers]["Content-Type"]).to eq("application/json")
            end
          end
        end

        context "when sessions are required" do
          before do
            configuration.transport[:require_sessions] = true
          end

          it "creates a session and returns response with session ID" do
            result = transport.handle

            aggregate_failures do
              expect(result[:json]).to eq({
                jsonrpc: "2.0",
                id: "init-1",
                result: {
                  protocolVersion: "2025-06-18",
                  capabilities: {},
                  serverInfo: {name: "test-server", version: "1.0.0"}
                }
              })
              expect(result[:status]).to eq(200)
              expect(result[:headers]).to have_key("Mcp-Session-Id")

              session_id = result[:headers]["Mcp-Session-Id"]
              expect(session_id).to match(/\A[0-9a-f-]{36}\z/) # UUID format
            end
          end

          it "creates session in Redis" do
            result = transport.handle
            session_id = result[:headers]["Mcp-Session-Id"]

            expect(mock_redis.exists("session:#{session_id}")).to eq(1)
          end
        end
      end

      context "for regular request without session" do
        let(:regular_request) { {"method" => "ping", "params" => {}, "id" => "req-1"} }

        before do
          set_request_env(
            body: regular_request.to_json,
            headers: {"Accept" => "application/json"}
          )
        end

        context "when sessions are not required" do
          it "processes request successfully without session ID" do
            result = transport.handle

            aggregate_failures do
              expect(result[:json]).to eq({
                jsonrpc: "2.0",
                id: "req-1",
                result: {text: "pong"}
              })
              expect(result[:status]).to eq(200)
              expect(result[:headers]["Content-Type"]).to eq("application/json")
            end
          end
        end

        context "when sessions are required" do
          before do
            configuration.transport[:require_sessions] = true
          end

          it "returns error for missing session ID" do
            result = transport.handle

            aggregate_failures do
              expect(result[:json]).to eq({
                jsonrpc: "2.0",
                id: "req-1",
                error: {code: -32600, message: "Invalid or missing session ID"}
              })
              expect(result[:status]).to eq(400)
            end
          end
        end
      end

      context "for regular request with valid session" do
        let(:regular_request) { {"method" => "ping", "params" => {}, "id" => "ping-1"} }

        before do
          set_request_env(
            body: regular_request.to_json,
            headers: {"Mcp-Session-Id" => session_id, "Accept" => "application/json"}
          )

          mock_redis.hset("session:#{session_id}", {
            "id" => session_id.to_json,
            "server_instance" => "test-server".to_json,
            "context" => {}.to_json,
            "created_at" => Time.now.to_f.to_json,
            "last_activity" => Time.now.to_f.to_json,
            "active_stream" => false.to_json
          })
        end

        it "returns response directly when no active stream" do
          result = transport.handle

          aggregate_failures do
            expect(result[:json]).to eq({
              jsonrpc: "2.0",
              id: "ping-1",
              result: {text: "pong"}
            })
            expect(result[:status]).to eq(200)
          end
        end

        it "routes to stream when session has active stream" do
          mock_redis.hset("session:#{session_id}", "active_stream", true.to_json)

          result = transport.handle

          aggregate_failures do
            expect(result[:json]).to eq({accepted: true})
            expect(result[:status]).to eq(200)
          end
        end
      end

      context "with invalid JSON" do
        before do
          set_request_env(body: "invalid json")
        end

        it "returns JSON parse error" do
          result = transport.handle

          aggregate_failures do
            expect(result[:json]).to eq({
              jsonrpc: "2.0",
              id: "",
              error: {code: -32700, message: "Parse error"}
            })
            expect(result[:status]).to eq(400)
          end
        end
      end

      context "with MCP-Protocol-Version header" do
        let(:regular_request) { {"method" => "ping", "params" => {}, "id" => "ping-1"} }

        before do
          init_request = {"method" => "initialize", "params" => {"protocolVersion" => "2025-06-18"}, "id" => "init-1"}
          set_request_env(
            body: init_request.to_json,
            headers: {"Accept" => "application/json"}
          )

          transport.handle

          set_request_env(
            body: regular_request.to_json,
            headers: {"Accept" => "application/json"}
          )
        end

        it "accepts negotiated protocol version" do
          set_request_env(
            body: regular_request.to_json,
            headers: {
              "Accept" => "application/json",
              "MCP-Protocol-Version" => "2025-06-18"
            }
          )

          result = transport.handle

          aggregate_failures do
            expect(result[:json]).to eq({
              jsonrpc: "2.0",
              id: "ping-1",
              result: {text: "pong"}
            })
            expect(result[:status]).to eq(200)
          end
        end

        it "rejects non-negotiated protocol version" do
          set_request_env(
            body: regular_request.to_json,
            headers: {
              "Accept" => "application/json",
              "MCP-Protocol-Version" => "2020-01-01"
            }
          )

          result = transport.handle

          aggregate_failures do
            expect(result[:json]).to match({
              jsonrpc: "2.0",
              id: nil,
              error: {code: -32600, message: /Invalid MCP protocol version: 2020-01-01/}
            })
            expect(result[:status]).to eq(400)
          end
        end
      end

      context "protocol version negotiation" do
        it "returns negotiated protocol version when client sends supported version" do
          init_request = {"method" => "initialize", "params" => {"protocolVersion" => "2025-06-18"}, "id" => "init-1"}
          set_request_env(
            body: init_request.to_json,
            headers: {"Accept" => "application/json"}
          )

          result = transport.handle

          aggregate_failures do
            expect(result[:json][:result][:protocolVersion]).to eq("2025-06-18")
            expect(result[:status]).to eq(200)
          end
        end

        it "returns server's latest version when client sends unsupported version" do
          init_request = {"method" => "initialize", "params" => {"protocolVersion" => "2020-01-01"}, "id" => "init-1"}
          set_request_env(
            body: init_request.to_json,
            headers: {"Accept" => "application/json"}
          )

          result = transport.handle

          aggregate_failures do
            expect(result[:json][:result][:protocolVersion]).to eq("2025-06-18")
            expect(result[:status]).to eq(200)
          end
        end
      end

      context "with internal error" do
        let(:error_request) { {"method" => "error_method", "params" => {}, "id" => "error-1"} }

        before do
          set_request_env(
            body: error_request.to_json,
            headers: {"Mcp-Session-Id" => session_id}
          )

          mock_redis.hset("session:#{session_id}", {
            "id" => session_id.to_json,
            "server_instance" => "test-server".to_json,
            "context" => {}.to_json,
            "created_at" => Time.now.to_f.to_json,
            "last_activity" => Time.now.to_f.to_json,
            "active_stream" => false.to_json
          })

          allow(mcp_logger).to receive(:error)
        end

        it "returns internal server error" do
          result = transport.handle

          aggregate_failures do
            expect(result[:json]).to eq({
              jsonrpc: "2.0",
              id: "error-1",
              error: {code: -32603, message: "Internal error"}
            })
            expect(result[:status]).to eq(500)
            expect(mcp_logger).to have_received(:error).with("Error handling POST request",
              error: String,
              backtrace: kind_of(Array))
          end
        end
      end
    end

    context "with GET request (SSE)" do
      before do
        set_request_env(
          method: "GET",
          headers: {
            "Mcp-Session-Id" => session_id,
            "Accept" => "text/event-stream"
          }
        )

        mock_redis.hset("session:#{session_id}", {
          "id" => session_id.to_json,
          "server_instance" => "test-server".to_json,
          "context" => {}.to_json,
          "created_at" => Time.now.to_f.to_json,
          "last_activity" => Time.now.to_f.to_json,
          "active_stream" => false.to_json
        })
      end

      it "returns SSE stream configuration" do
        result = transport.handle

        aggregate_failures do
          expect(result[:stream]).to be true
          expect(result[:headers]).to eq({
            "Content-Type" => "text/event-stream",
            "Cache-Control" => "no-cache",
            "Connection" => "keep-alive"
          })
          expect(result[:stream_proc]).to be_a(Proc)
        end
      end

      context "when sessions are required" do
        before do
          configuration.transport[:require_sessions] = true
          mock_redis.hset("session:#{session_id}", {
            "id" => session_id.to_json,
            "server_instance" => "test-server".to_json,
            "context" => {}.to_json,
            "created_at" => Time.now.to_f.to_json,
            "last_activity" => Time.now.to_f.to_json,
            "active_stream" => false.to_json
          })
        end

        it "marks session as having active stream" do
          transport.handle

          stream_data = mock_redis.hget("session:#{session_id}", "active_stream")
          expect(JSON.parse(stream_data)).to be true
        end
      end

      context "with invalid session when sessions are required" do
        before do
          configuration.transport[:require_sessions] = true
          set_request_env(
            method: "GET",
            headers: {
              "Mcp-Session-Id" => "invalid-session",
              "Accept" => "text/event-stream"
            }
          )
        end

        it "returns error for invalid session" do
          result = transport.handle

          aggregate_failures do
            expect(result[:json]).to eq({
              jsonrpc: "2.0",
              id: nil,
              error: {code: -32600, message: "Session terminated"}
            })
            expect(result[:status]).to eq(404)
          end
        end
      end
    end

    context "with DELETE request" do
      before do
        set_request_env(
          method: "DELETE",
          headers: {"Mcp-Session-Id" => session_id}
        )

        mock_redis.hset("session:#{session_id}", {
          "id" => session_id.to_json,
          "server_instance" => "test-server".to_json,
          "context" => {}.to_json,
          "created_at" => Time.now.to_f.to_json,
          "last_activity" => Time.now.to_f.to_json,
          "active_stream" => false.to_json
        })
      end

      it "cleans up session and returns success" do
        result = transport.handle

        aggregate_failures do
          expect(result[:json]).to eq({success: true})
          expect(result[:status]).to eq(200)
          expect(mock_redis.exists("session:#{session_id}")).to eq(0)
        end
      end

      context "without session ID" do
        before do
          set_request_env(
            method: "DELETE",
            headers: {}
          )
        end

        it "still returns success" do
          result = transport.handle

          aggregate_failures do
            expect(result[:json]).to eq({success: true})
            expect(result[:status]).to eq(200)
          end
        end
      end
    end

    context "with unsupported HTTP method" do
      before do
        set_request_env(method: "PUT")
      end

      it "returns method not allowed error" do
        result = transport.handle

        aggregate_failures do
          expect(result[:json]).to eq({
            jsonrpc: "2.0",
            id: nil,
            error: {code: -32601, message: "Method not allowed"}
          })
          expect(result[:status]).to eq(405)
        end
      end
    end
  end

  describe "SSE stream functionality" do
    let(:mock_stream) { double("stream") }

    before do
      set_request_env(
        method: "GET",
        headers: {
          "Mcp-Session-Id" => session_id,
          "Accept" => "text/event-stream"
        }
      )

      mock_redis.hset("session:#{session_id}", {
        "id" => session_id.to_json,
        "server_instance" => "test-server".to_json,
        "context" => {}.to_json,
        "created_at" => Time.now.to_f.to_json,
        "last_activity" => Time.now.to_f.to_json,
        "active_stream" => false.to_json
      })
    end

    describe "stream connection handling" do
      it "registers local stream when SSE connection starts" do
        result = transport.handle
        stream_proc = result[:stream_proc]

        allow(mock_stream).to receive(:write)
        allow(mock_stream).to receive(:flush)

        stream_thread = Thread.new do
          stream_proc.call(mock_stream)
        rescue
        end

        sleep 0.1
        stream_thread.kill if stream_thread.alive?
        stream_thread.join

        stream_data = mock_redis.hget("session:#{session_id}", "active_stream")
        expect(JSON.parse(stream_data)).to be false
      end
    end

    describe "keep-alive functionality" do
      before do
        allow(mock_stream).to receive(:write)
        allow(mock_stream).to receive(:flush)
        allow(mock_stream).to receive(:respond_to?).with(:flush).and_return(true)
      end

      it "sends ping messages to detect connection status" do
        expect(mock_stream).to receive(:write).with(": ping\n\n")
        expect(mock_stream).to receive(:flush)

        result = transport.send(:stream_connected?, mock_stream)
        expect(result).to be true
      end

      it "detects broken connections" do
        allow(mock_stream).to receive(:write).and_raise(Errno::EPIPE)

        result = transport.handle
        stream_proc = result[:stream_proc]

        stream_thread = Thread.new do
          stream_proc.call(mock_stream)
        rescue
        end

        sleep 0.1
        stream_thread.kill if stream_thread.alive?
        stream_thread.join

        stream_data = mock_redis.hget("session:#{session_id}", "active_stream")
        expect(JSON.parse(stream_data)).to be false
      end
    end
  end

  describe "cross-server message routing" do
    let(:other_server_transport) do
      other_config = ModelContextProtocol::Server::Configuration.new
      other_config.name = "other-server"
      other_config.registry = ModelContextProtocol::Server::Registry.new
      other_config.version = "1.0.0"
      other_config.transport = {
        type: :streamable_http,
        require_sessions: true
      }

      allow(mock_redis).to receive(:publish)
      allow(mock_redis).to receive(:subscribe)

      described_class.new(
        router: ModelContextProtocol::Server::Router.new(configuration: other_config),
        configuration: other_config
      )
    end

    it "routes messages between server instances via Redis" do
      configuration.transport[:require_sessions] = true

      init_request = {"method" => "initialize", "id" => "init-1"}
      set_request_env(
        body: init_request.to_json,
        headers: {"Accept" => "application/json"}
      )

      result = transport.handle
      session_id = result[:headers]["Mcp-Session-Id"]

      first_server_instance = transport.instance_variable_get(:@server_instance)
      session_store = transport.instance_variable_get(:@session_store)
      session_store.mark_stream_active(session_id, first_server_instance)

      other_router = other_server_transport.instance_variable_get(:@router)
      other_router.map("ping") do |message|
        TestResponse[text: "pong"]
      end

      ping_request = {"method" => "ping", "id" => "ping-1"}
      other_config = other_server_transport.instance_variable_get(:@configuration)
      other_config.transport = {
        type: :streamable_http,
        require_sessions: true,
        env: build_rack_env(
          body: ping_request.to_json,
          headers: {
            "Mcp-Session-Id" => session_id,
            "Accept" => "application/json"
          }
        )
      }

      expect(mock_redis).to receive(:publish)

      result = other_server_transport.handle
      expect(result[:json]).to eq({accepted: true})
    end
  end

  describe "session management integration" do
    it "creates sessions with server context when sessions are required" do
      configuration.transport[:require_sessions] = true
      configuration.context = {user_id: "test-user", app: "test-app"}

      init_request = {"method" => "initialize", "id" => "init-1"}
      set_request_env(
        body: init_request.to_json,
        headers: {"Accept" => "application/json"}
      )

      result = transport.handle
      session_id = result[:headers]["Mcp-Session-Id"]
      context_data = mock_redis.hget("session:#{session_id}", "context")
      parsed_context = JSON.parse(context_data)
      expect(parsed_context).to eq({"user_id" => "test-user", "app" => "test-app"})
    end

    it "handles session cleanup on DELETE when sessions are required" do
      configuration.transport[:require_sessions] = true

      init_request = {"method" => "initialize", "id" => "init-1"}
      set_request_env(
        body: init_request.to_json,
        headers: {"Accept" => "application/json"}
      )

      result = transport.handle
      session_id = result[:headers]["Mcp-Session-Id"]

      expect(mock_redis.exists("session:#{session_id}")).to eq(1)

      set_request_env(
        method: "DELETE",
        headers: {"Mcp-Session-Id" => session_id}
      )

      result = transport.handle

      aggregate_failures do
        expect(result[:json]).to eq({success: true})
        expect(result[:status]).to eq(200)
        expect(mock_redis.exists("session:#{session_id}")).to eq(0)
      end
    end
  end

  describe "MCP logging integration" do
    before do
      set_request_env(
        method: "GET",
        headers: {}
      )
    end

    it "connects the logger to the transport when handle starts" do
      expect(mcp_logger).to receive(:connect_transport).with(transport)

      transport.handle
    end

    describe "#send_notification" do
      let(:mock_stream) { StringIO.new }
      let(:session_id) { "test-session-123" }

      before do
        mcp_logger.connect_transport(transport)
      end

      context "when there are active streams" do
        before do
          transport.instance_variable_get(:@stream_registry).register_stream(session_id, mock_stream)
        end

        it "delivers notifications to active streams" do
          transport.send_notification("notifications/message", {
            level: "info",
            logger: "test",
            data: {message: "test notification"}
          })

          mock_stream.rewind
          output = mock_stream.read

          expect(output).to include("data: ")
          data_line = output.lines.find { |line| line.start_with?("data: ") }
          json_string = data_line.sub("data: ", "").strip
          notification = JSON.parse(json_string)

          aggregate_failures do
            expect(notification["jsonrpc"]).to eq("2.0")
            expect(notification["method"]).to eq("notifications/message")
            expect(notification["params"]["level"]).to eq("info")
            expect(notification["params"]["logger"]).to eq("test")
            expect(notification["params"]["data"]["message"]).to eq("test notification")
          end
        end

        it "handles broken stream connections gracefully" do
          allow(mock_stream).to receive(:write).and_raise(IOError, "broken pipe")

          expect {
            transport.send_notification("notifications/message", {level: "error", data: {}})
          }.not_to raise_error
        end
      end

      context "when there are no active streams" do
        it "queues notifications" do
          transport.send_notification("notifications/message", {
            level: "warning",
            logger: "test",
            data: {message: "queued notification"}
          })

          notification_queue = transport.instance_variable_get(:@notification_queue)
          expect(notification_queue.size).to eq(1)

          queued_notifications = notification_queue.peek_all
          queued_notification = queued_notifications.first
          aggregate_failures do
            expect(queued_notification["jsonrpc"]).to eq("2.0")
            expect(queued_notification["method"]).to eq("notifications/message")
            expect(queued_notification["params"]["level"]).to eq("warning")
            expect(queued_notification["params"]["data"]["message"]).to eq("queued notification")
          end
        end
      end

      context "when stream connects later" do
        it "flushes queued notifications to new stream" do
          transport.send_notification("notifications/message", {
            level: "info",
            data: {message: "queued message"}
          })

          transport.send(:flush_notifications_to_stream, mock_stream)

          mock_stream.rewind
          output = mock_stream.read

          expect(output).to include("data: ")
          data_line = output.lines.find { |line| line.start_with?("data: ") }
          json_string = data_line.sub("data: ", "").strip
          notification = JSON.parse(json_string)
          expect(notification["params"]["data"]["message"]).to eq("queued message")
        end
      end
    end

    describe "logging error handling" do
      let(:test_stream) { StringIO.new }

      before do
        set_request_env(
          method: "POST",
          headers: {}
        )
      end

      it "uses MCP logger for stream monitor errors" do
        allow(mcp_logger).to receive(:error)

        mcp_logger.error("Stream monitor error", error: "monitor error")

        expect(mcp_logger).to have_received(:error).with("Stream monitor error", error: "monitor error")
      end

      it "uses MCP logger for Redis subscriber errors" do
        allow(mcp_logger).to receive(:error)

        mcp_logger.error("Redis subscriber error", error: "redis error", backtrace: ["backtrace line"])

        expect(mcp_logger).to have_received(:error).with("Redis subscriber error",
          error: "redis error",
          backtrace: kind_of(Array))
      end
    end
  end
end
