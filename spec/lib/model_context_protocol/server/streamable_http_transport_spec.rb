require "spec_helper"

RSpec.describe ModelContextProtocol::Server::StreamableHttpTransport do
  subject(:transport) { server.transport }

  let(:server) do
    ModelContextProtocol::Server.new do |config|
      config.name = "test-server"
      config.version = "1.0.0"
      config.registry = ModelContextProtocol::Server::Registry.new
      config.transport = {
        type: :streamable_http,
        require_sessions: false,
        validate_origin: false,
        env: rack_env
      }
    end
  end
  let(:router) { server.router }
  let(:mock_redis) { MockRedis.new }
  let(:client_logger) { server.configuration.client_logger }
  let(:server_logger) { server.configuration.server_logger }
  let(:rack_env) { build_rack_env }
  let(:session_id) { "test-session-123" }
  let(:configuration) { server.configuration }

  before(:all) do
    ModelContextProtocol::Server.configure_redis do |config|
      config.redis_url = "redis://localhost:6379/15"
    end

    # Configure server logging to use a silent logger for tests
    ModelContextProtocol::Server.configure_server_logging do |config|
      config.logdev = File::NULL
      config.level = Logger::FATAL
    end
  end

  before(:each) do
    allow(ModelContextProtocol::Server::RedisConfig.pool).to receive(:checkout).and_return(mock_redis)
    allow(ModelContextProtocol::Server::RedisConfig.pool).to receive(:checkin)

    # Allow server_logger calls for verification
    allow(server_logger).to receive(:info).and_call_original
    allow(server_logger).to receive(:debug).and_call_original
    allow(server_logger).to receive(:error).and_call_original
  end

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
    configuration.transport[:env] = build_rack_env(method:, body:, headers:)
  end

  before do
    mock_redis.flushdb

    monitor_thread = double("monitor_thread", alive?: false, kill: nil, join: nil, name: nil)
    poller_thread = double("poller_thread", alive?: false, kill: nil, join: nil, name: nil)
    allow(poller_thread).to receive(:name=)

    allow(Thread).to receive(:new).and_call_original
    allow(Thread).to receive(:new).with(no_args).and_return(monitor_thread, poller_thread)

    server.start
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
                  capabilities: {completions: {}, logging: {}},
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
            new_transport = ModelContextProtocol::Server::StreamableHttpTransport.new(
              router: server.router,
              configuration: configuration
            )
            server.instance_variable_set(:@transport, new_transport)
          end

          it "creates a session and returns response with session ID" do
            result = transport.handle

            aggregate_failures do
              expect(result[:json]).to eq({
                jsonrpc: "2.0",
                id: "init-1",
                result: {
                  protocolVersion: "2025-06-18",
                  capabilities: {completions: {}, logging: {}},
                  serverInfo: {name: "test-server", version: "1.0.0"}
                }
              })
              expect(result[:status]).to eq(200)
              expect(result[:headers]).to have_key("Mcp-Session-Id")

              session_id = result[:headers]["Mcp-Session-Id"]
              expect(session_id).to match(/\A[0-9a-f-]{36}\z/)
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
                result: {}
              })
              expect(result[:status]).to eq(200)
              expect(result[:headers]["Content-Type"]).to eq("application/json")
            end
          end
        end

        context "when sessions are required" do
          before do
            configuration.transport[:require_sessions] = true
            new_transport = ModelContextProtocol::Server::StreamableHttpTransport.new(
              router: server.router,
              configuration: configuration
            )
            server.instance_variable_set(:@transport, new_transport)
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
              result: {}
            })
            expect(result[:status]).to eq(200)
          end
        end

        it "returns JSON response even when session has active stream (honors Accept header)" do
          mock_redis.hset("session:#{session_id}", "active_stream", true.to_json)

          result = transport.handle

          aggregate_failures do
            expect(result[:json]).to eq({
              jsonrpc: "2.0",
              id: "ping-1",
              result: {}
            })
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
              result: {}
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

          allow(client_logger).to receive(:error)
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
            expect(server_logger).to have_received(:error).at_least(:once)
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
          new_transport = ModelContextProtocol::Server::StreamableHttpTransport.new(
            router: server.router,
            configuration: configuration
          )
          server.instance_variable_set(:@transport, new_transport)

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
          new_transport = ModelContextProtocol::Server::StreamableHttpTransport.new(
            router: server.router,
            configuration: configuration
          )
          server.instance_variable_set(:@transport, new_transport)

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
          session_store = transport.instance_variable_get(:@session_store)
          expect(session_store.session_exists?(session_id)).to eq(false)
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
        allow(mock_stream).to receive(:respond_to?).with(:closed?).and_return(false)
      end

      it "checks connection status without sending pings" do
        # stream_connected? now only checks stream status, actual pings are sent via monitor_streams
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
    it "returns JSON response regardless of cross-server sessions (honors Accept header)" do
      configuration.transport[:require_sessions] = true
      new_transport = ModelContextProtocol::Server::StreamableHttpTransport.new(
        router: server.router,
        configuration: configuration
      )
      server.instance_variable_set(:@transport, new_transport)

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

      ping_request = {"method" => "ping", "id" => "ping-1"}
      second_server = ModelContextProtocol::Server.new do |config|
        config.name = "other-server"
        config.version = "1.0.0"
        config.registry = ModelContextProtocol::Server::Registry.new
        config.transport = {
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
      end

      second_transport = ModelContextProtocol::Server::StreamableHttpTransport.new(
        router: second_server.router,
        configuration: second_server.configuration
      )

      result = second_transport.handle
      expect(result[:json]).to eq({
        jsonrpc: "2.0",
        id: "ping-1",
        result: {}
      })

      # The response should be returned as JSON regardless of cross-server session state
      # We no longer queue messages when Accept header explicitly requests JSON
    end
  end

  describe "session management integration" do
    it "creates sessions with server context when sessions are required" do
      configuration.transport[:require_sessions] = true
      configuration.context = {user_id: "test-user", app: "test-app"}
      new_transport = ModelContextProtocol::Server::StreamableHttpTransport.new(
        router: server.router,
        configuration: configuration
      )
      server.instance_variable_set(:@transport, new_transport)

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
      new_transport = ModelContextProtocol::Server::StreamableHttpTransport.new(
        router: server.router,
        configuration: configuration
      )
      server.instance_variable_set(:@transport, new_transport)

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
        session_store = transport.instance_variable_get(:@session_store)
        expect(session_store.session_exists?(session_id)).to eq(false)
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

    it "logs debug message when handle starts" do
      expect(server_logger).to receive(:debug).with("Handling streamable HTTP transport request")

      transport.handle
    end

    describe "#send_notification" do
      let(:mock_stream) { StringIO.new }
      let(:session_id) { "test-session-123" }

      before do
        client_logger.connect_transport(transport)
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
        allow(client_logger).to receive(:error)

        client_logger.error("Stream monitor error", error: "monitor error")

        expect(client_logger).to have_received(:error).with("Stream monitor error", error: "monitor error")
      end

      it "uses MCP logger for message poller errors" do
        allow(client_logger).to receive(:error)

        client_logger.error("Error in message polling", error: "polling error")

        expect(client_logger).to have_received(:error).with("Error in message polling",
          error: "polling error")
      end
    end
  end

  describe "transport parameter passing to router" do
    before do
      router.map("test_method") do |_|
        double("result", serialized: {success: true})
      end

      mock_redis.hset("session:#{session_id}", {
        "id" => session_id.to_json,
        "server_instance" => "test-server".to_json,
        "context" => {}.to_json,
        "created_at" => Time.now.to_f.to_json,
        "last_activity" => Time.now.to_f.to_json,
        "active_stream" => false.to_json
      })
    end

    context "when handling initialization requests" do
      let(:init_request) do
        {
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "initialize",
          "params" => {
            "protocolVersion" => "2025-03-26",
            "capabilities" => {},
            "clientInfo" => {"name" => "test-client"}
          }
        }
      end

      before do
        set_request_env(
          body: init_request.to_json,
          headers: {"Accept" => "application/json"}
        )
      end

      it "passes transport parameter to router.route for initialization" do
        allow(router).to receive(:route).and_call_original

        transport.handle

        expect(router).to have_received(:route).with(
          init_request,
          hash_including(transport: transport)
        )
      end
    end

    context "when handling regular requests with sessions" do
      let(:regular_request) do
        {
          "jsonrpc" => "2.0",
          "id" => 2,
          "method" => "test_method",
          "params" => {"data" => "test"}
        }
      end

      before do
        configuration.transport[:require_sessions] = true
        new_transport = ModelContextProtocol::Server::StreamableHttpTransport.new(
          router: server.router,
          configuration: configuration
        )
        server.instance_variable_set(:@transport, new_transport)

        set_request_env(
          body: regular_request.to_json,
          headers: {"Mcp-Session-Id" => session_id, "Accept" => "application/json"}
        )
      end

      it "passes transport parameter along with request_store and session_id" do
        transport = server.transport
        allow(router).to receive(:route).and_call_original

        transport.handle

        expect(router).to have_received(:route).with(
          regular_request,
          hash_including(
            request_store: transport.instance_variable_get(:@request_store),
            session_id: session_id,
            transport: transport
          )
        )
      end
    end

    context "when handling regular requests without sessions" do
      let(:regular_request) do
        {
          "jsonrpc" => "2.0",
          "id" => 3,
          "method" => "test_method",
          "params" => {"data" => "test"}
        }
      end

      before do
        set_request_env(
          body: regular_request.to_json,
          headers: {"Accept" => "application/json"}
        )
      end

      it "passes transport parameter with request_store but no session_id" do
        allow(router).to receive(:route).and_call_original

        transport.handle

        expect(router).to have_received(:route).with(
          regular_request,
          hash_including(
            request_store: transport.instance_variable_get(:@request_store),
            transport: transport
          )
        )

        # Verify session_id is nil when sessions not required
        expect(router).to have_received(:route).with(
          regular_request,
          hash_including(session_id: nil)
        )
      end
    end
  end

  describe "cancellation handling" do
    let(:request_id) { "test-request-123" }
    let(:reason) { "User requested cancellation" }
    let(:cancellation_message) do
      {
        "method" => "notifications/cancelled",
        "params" => {
          "requestId" => request_id,
          "reason" => reason
        }
      }
    end

    before do
      allow(client_logger).to receive(:debug)
      allow(client_logger).to receive(:error)
    end

    describe "#handle_cancellation" do
      context "when request exists in store" do
        before do
          request_store = transport.instance_variable_get(:@request_store)
          request_store.register_request(request_id, session_id)
        end

        it "marks the request as cancelled" do
          transport.send(:handle_cancellation, cancellation_message, session_id)

          request_store = transport.instance_variable_get(:@request_store)
          expect(request_store.cancelled?(request_id)).to be true
        end

        it "stores cancellation reason" do
          transport.send(:handle_cancellation, cancellation_message, session_id)

          request_store = transport.instance_variable_get(:@request_store)
          cancellation_info = request_store.get_cancellation_info(request_id)
          expect(cancellation_info["reason"]).to eq(reason)
        end
      end

      context "when request does not exist in store" do
        it "does not raise error for unknown request" do
          expect {
            transport.send(:handle_cancellation, cancellation_message, session_id)
          }.not_to raise_error
        end
      end

      context "with malformed cancellation message" do
        it "handles missing params gracefully" do
          malformed_message = {"method" => "notifications/cancelled"}

          expect {
            transport.send(:handle_cancellation, malformed_message, session_id)
          }.not_to raise_error
        end

        it "handles missing request ID gracefully" do
          malformed_message = {
            "method" => "notifications/cancelled",
            "params" => {"reason" => "test reason"}
          }

          expect {
            transport.send(:handle_cancellation, malformed_message, session_id)
          }.not_to raise_error
        end
      end

      context "when cancellation without reason" do
        let(:cancellation_without_reason) do
          {
            "method" => "notifications/cancelled",
            "params" => {"requestId" => request_id}
          }
        end

        before do
          request_store = transport.instance_variable_get(:@request_store)
          request_store.register_request(request_id, session_id)
        end

        it "marks request as cancelled with nil reason" do
          transport.send(:handle_cancellation, cancellation_without_reason, session_id)

          request_store = transport.instance_variable_get(:@request_store)
          cancellation_info = request_store.get_cancellation_info(request_id)
          expect(cancellation_info["reason"]).to be_nil
        end
      end

      context "when Redis operation fails" do
        before do
          request_store = transport.instance_variable_get(:@request_store)
          allow(request_store).to receive(:mark_cancelled).and_raise(StandardError.new("Redis connection failed"))
        end

        it "does not raise error on Redis failures" do
          expect {
            transport.send(:handle_cancellation, cancellation_message, session_id)
          }.not_to raise_error
        end
      end
    end

    describe "integration with request processing" do
      let(:regular_request) { {"method" => "ping", "params" => {}, "id" => request_id} }

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

      it "registers and unregisters requests during processing" do
        transport.handle

        request_store = transport.instance_variable_get(:@request_store)
        expect(request_store.active?(request_id)).to be false
      end

      it "cleans up request from store after processing" do
        transport.handle

        request_store = transport.instance_variable_get(:@request_store)
        expect(request_store.active?(request_id)).to be false
      end

      it "provides cancellation context to handlers" do
        result = transport.handle

        aggregate_failures do
          expect(result[:status]).to eq(200)
          expect(result[:json]).to include(:jsonrpc, :id, :result)
        end
      end
    end

    describe "progressive streaming for requests with progress tokens" do
      let(:mock_stream) { StringIO.new }
      let(:progress_request) do
        {
          "jsonrpc" => "2.0",
          "method" => "tools/call",
          "params" => {
            "_meta" => {"progressToken" => 123},
            "name" => "test_tool",
            "arguments" => {}
          },
          "id" => "progressive-1"
        }
      end

      before do
        allow(router).to receive(:route) do |message, **kwargs|
          transport = kwargs[:transport]

          transport.send_notification("notifications/progress", {
            progressToken: 123,
            progress: 50.0,
            total: 100,
            message: "Processing..."
          })

          transport.send_notification("notifications/progress", {
            progressToken: 123,
            progress: 100.0,
            total: 100,
            message: "Completed"
          })

          double("result", serialized: {content: [{type: "text", text: "Tool completed"}], isError: false})
        end

        set_request_env(
          body: progress_request.to_json,
          headers: {"Accept" => "application/json"}
        )
      end

      it "respects Accept header preference for JSON over streaming with progress tokens" do
        result = transport.handle

        aggregate_failures do
          expect(result[:stream]).to be_nil
          expect(result[:json]).not_to be_nil
          expect(result[:headers]["Content-Type"]).to eq("application/json")
          expect(result[:json][:id]).to eq("progressive-1")
          expect(result[:json][:result]).not_to be_nil
        end
      end

      it "does not send progress notifications when using JSON response format" do
        # Since Accept: application/json is set, no progress notifications should be sent
        # and we should get a regular JSON response
        result = transport.handle

        aggregate_failures do
          expect(result[:stream]).to be_nil
          expect(result[:json]).not_to be_nil
          expect(result[:json][:id]).to eq("progressive-1")
        end
      end
    end

    describe "progressive streaming when client accepts SSE" do
      let(:mock_stream) { StringIO.new }
      let(:progress_request) do
        {
          "jsonrpc" => "2.0",
          "method" => "tools/call",
          "params" => {
            "_meta" => {"progressToken" => 123},
            "name" => "test_tool",
            "arguments" => {}
          },
          "id" => "progressive-1"
        }
      end

      before do
        allow(router).to receive(:route) do |message, **kwargs|
          transport = kwargs[:transport]

          transport.send_notification("notifications/progress", {
            progressToken: 123,
            progress: 50.0,
            total: 100,
            message: "Processing..."
          })

          transport.send_notification("notifications/progress", {
            progressToken: 123,
            progress: 100.0,
            total: 100,
            message: "Completed"
          })

          double("result", serialized: {content: [{type: "text", text: "Tool completed"}], isError: false})
        end

        set_request_env(
          body: progress_request.to_json,
          headers: {"Accept" => "text/event-stream"}
        )
      end

      it "streams responses for requests with progress tokens when client accepts SSE" do
        result = transport.handle

        aggregate_failures do
          expect(result[:stream]).to be true
          expect(result[:headers]["Content-Type"]).to eq("text/event-stream")
          expect(result[:headers]["Cache-Control"]).to eq("no-cache")
          expect(result[:headers]["Connection"]).to eq("keep-alive")
          expect(result[:stream_proc]).to be_a(Proc)
        end
      end

      it "delivers progress notifications through the stream" do
        received_events = []

        allow_any_instance_of(StringIO).to receive(:write) do |instance, data|
          if data.start_with?("data: ")
            event_data = data[6..-3]
            begin
              parsed_data = JSON.parse(event_data)
              received_events << parsed_data
            rescue JSON::ParserError
              nil
            end
          end
          data.length
        end

        result = transport.handle
        result[:stream_proc].call(mock_stream)
        progress_notifications = received_events.select { |event| event["method"] == "notifications/progress" }
        final_responses = received_events.select { |event| event.key?("result") }

        aggregate_failures do
          expect(progress_notifications.size).to eq(2)
          expect(progress_notifications[0]["params"]["progress"]).to eq(50.0)
          expect(progress_notifications[1]["params"]["progress"]).to eq(100.0)
          expect(final_responses.size).to eq(1)
          expect(final_responses[0]["id"]).to eq("progressive-1")
        end
      end

      it "registers and unregisters streams properly" do
        stream_registry = transport.instance_variable_get(:@stream_registry)

        expect(stream_registry.has_any_local_streams?).to be false

        result = transport.handle
        result[:stream_proc].call(mock_stream)

        expect(stream_registry.has_any_local_streams?).to be false
      end

      context "when request does not have progress token" do
        let(:regular_request) do
          {
            "jsonrpc" => "2.0",
            "method" => "tools/call",
            "params" => {"name" => "test_tool", "arguments" => {}},
            "id" => "regular-1"
          }
        end

        before do
          allow(router).to receive(:route).and_return(
            double("result", serialized: {content: [{type: "text", text: "Tool completed"}], isError: false})
          )

          set_request_env(
            body: regular_request.to_json,
            headers: {"Accept" => "application/json"}
          )
        end

        it "returns JSON response instead of streaming" do
          result = transport.handle

          aggregate_failures do
            expect(result[:stream]).to be_nil
            expect(result[:json]).not_to be_nil
            expect(result[:status]).to eq(200)
            expect(result[:headers]["Content-Type"]).to eq("application/json")
          end
        end
      end

      context "when client explicitly requests SSE" do
        before do
          set_request_env(
            body: progress_request.to_json,
            headers: {"Accept" => "text/event-stream"}
          )
        end

        it "streams response even without progress token" do
          result = transport.handle

          aggregate_failures do
            expect(result[:stream]).to be true
            expect(result[:headers]["Content-Type"]).to eq("text/event-stream")
          end
        end

        context "intelligent streaming decisions with both Accept headers" do
          let(:progress_request_both) do
            {
              "jsonrpc" => "2.0",
              "method" => "tools/call",
              "params" => {
                "_meta" => {"progressToken" => 123},
                "name" => "test_tool",
                "arguments" => {}
              },
              "id" => "both-accept-1"
            }
          end

          before do
            allow(router).to receive(:route) do |message, **kwargs|
              double("result", serialized: {content: [{type: "text", text: "Tool completed"}], isError: false})
            end
          end

          it "streams by default when client accepts both (regardless of progress token)" do
            set_request_env(
              body: progress_request_both.to_json,
              headers: {"Accept" => "application/json, text/event-stream"}
            )

            result = transport.handle

            aggregate_failures do
              expect(result[:stream]).to be true
              expect(result[:json]).to be_nil
              expect(result[:headers]["Content-Type"]).to eq("text/event-stream")
            end
          end

          it "streams by default when client accepts both (regardless of progress token)" do
            request_without_token = progress_request_both.dup
            request_without_token["params"].delete("_meta")

            set_request_env(
              body: request_without_token.to_json,
              headers: {"Accept" => "application/json, text/event-stream"}
            )

            result = transport.handle

            aggregate_failures do
              expect(result[:stream]).to be true
              expect(result[:json]).to be_nil
              expect(result[:headers]["Content-Type"]).to eq("text/event-stream")
            end
          end

          it "returns JSON when client explicitly requests JSON only" do
            set_request_env(
              body: progress_request_both.to_json,
              headers: {"Accept" => "application/json"}
            )

            result = transport.handle

            aggregate_failures do
              expect(result[:stream]).to be_nil
              expect(result[:json]).not_to be_nil
              expect(result[:headers]["Content-Type"]).to eq("application/json")
            end
          end

          it "streams when client accepts both and response is large" do
            # Create a large response (>100KB)
            large_content = "x" * 150_000  # 150KB of content

            allow(router).to receive(:route) do |message, **kwargs|
              double("result", serialized: {content: [{type: "text", text: large_content}], isError: false})
            end

            set_request_env(
              body: progress_request_both.to_json,
              headers: {"Accept" => "application/json, text/event-stream"}
            )

            result = transport.handle

            aggregate_failures do
              expect(result[:stream]).to be true
              expect(result[:headers]["Content-Type"]).to eq("text/event-stream")
              expect(result[:stream_proc]).to be_a(Proc)
            end
          end
        end
      end
    end
  end

  describe "stream closing functionality" do
    let(:stream_registry) { transport.instance_variable_get(:@stream_registry) }
    let(:session_store) { transport.instance_variable_get(:@session_store) }
    let(:mock_stream) { double("stream") }
    let(:session_id) { "test-session-123" }

    before do
      allow(mock_stream).to receive(:write)
      allow(mock_stream).to receive(:flush)
      allow(mock_stream).to receive(:close)
    end

    describe "#close_stream" do
      context "when stream exists" do
        before do
          stream_registry.register_stream(session_id, mock_stream)
        end

        it "closes stream" do
          expect(mock_stream).to receive(:close)

          transport.send(:close_stream, session_id)
        end

        it "unregisters stream from registry" do
          allow(mock_stream).to receive(:close)

          expect(stream_registry.has_local_stream?(session_id)).to be true
          transport.send(:close_stream, session_id)
          expect(stream_registry.has_local_stream?(session_id)).to be false
        end

        it "marks session as inactive when sessions are required" do
          allow(transport.instance_variable_get(:@require_sessions)).to receive(:nil?).and_return(false)
          transport.instance_variable_set(:@require_sessions, true)

          allow(mock_stream).to receive(:close)
          expect(session_store).to receive(:mark_stream_inactive).with(session_id)

          transport.send(:close_stream, session_id)
        end

        it "handles already closed streams gracefully" do
          allow(mock_stream).to receive(:close).and_raise(IOError)

          expect { transport.send(:close_stream, session_id) }.not_to raise_error
          expect(stream_registry.has_local_stream?(session_id)).to be false
        end

        it "accepts custom reason for logging" do
          allow(mock_stream).to receive(:close)

          transport.send(:close_stream, session_id, reason: "custom_reason")
        end
      end

      context "when stream does not exist" do
        it "does nothing gracefully" do
          expect { transport.send(:close_stream, "nonexistent-session") }.not_to raise_error
        end
      end
    end

    describe "progressive request stream closing" do
      let(:progressive_request) do
        {
          "jsonrpc" => "2.0",
          "method" => "tools/call",
          "params" => {
            "name" => "test_tool",
            "arguments" => {},
            "_meta" => {"progressToken" => "test-token"}
          },
          "id" => "progressive-1"
        }
      end

      before do
        allow(router).to receive(:route).and_return(
          double("result", serialized: {content: [{type: "text", text: "Tool completed"}], isError: false})
        )

        set_request_env(
          body: progressive_request.to_json,
          headers: {"Accept" => "text/event-stream"}
        )
      end

      it "automatically closes stream after completing request" do
        allow(mock_stream).to receive(:write)
        expect(mock_stream).to receive(:close)

        result = transport.handle
        result[:stream_proc].call(mock_stream)
      end

      it "unregisters stream after completion" do
        allow(mock_stream).to receive(:write)
        allow(mock_stream).to receive(:close)

        result = transport.handle
        result[:stream_proc].call(mock_stream)

        # Stream should be cleaned up
        expect(stream_registry.has_any_local_streams?).to be false
      end

      it "handles client disconnect during processing" do
        allow(router).to receive(:route).and_raise(IOError)
        allow(mock_stream).to receive(:write)
        allow(mock_stream).to receive(:close)

        result = transport.handle
        expect { result[:stream_proc].call(mock_stream) }.not_to raise_error

        # Stream should still be cleaned up
        expect(stream_registry.has_any_local_streams?).to be false
      end
    end

    describe "enhanced disconnect detection" do
      before do
        stream_registry.register_stream(session_id, mock_stream)
      end

      describe "#stream_connected?" do
        it "returns true for open streams" do
          allow(mock_stream).to receive(:respond_to?).with(:closed?).and_return(true)
          allow(mock_stream).to receive(:closed?).and_return(false)

          expect(transport.send(:stream_connected?, mock_stream)).to be true
        end

        it "returns false for closed streams" do
          allow(mock_stream).to receive(:respond_to?).with(:closed?).and_return(true)
          allow(mock_stream).to receive(:closed?).and_return(true)

          expect(transport.send(:stream_connected?, mock_stream)).to be false
        end

        it "returns true for streams without closed? method" do
          allow(mock_stream).to receive(:respond_to?).with(:closed?).and_return(false)

          expect(transport.send(:stream_connected?, mock_stream)).to be true
        end

        it "returns false for nil streams" do
          expect(transport.send(:stream_connected?, nil)).to be false
        end
      end

      describe "#monitor_streams" do
        it "closes disconnected streams" do
          allow(mock_stream).to receive(:write).and_raise(IOError)
          allow(mock_stream).to receive(:close)

          transport.send(:monitor_streams)

          expect(stream_registry.has_local_stream?(session_id)).to be false
        end

        it "refreshes heartbeat for connected streams" do
          allow(mock_stream).to receive(:write)
          allow(mock_stream).to receive(:flush)

          expect(stream_registry).to receive(:refresh_heartbeat).with(session_id)

          transport.send(:monitor_streams)
        end

        it "handles network errors during monitoring" do
          # Make get_all_local_streams return the streams first, then fail during processing
          allow(stream_registry).to receive(:get_all_local_streams).and_return({session_id => mock_stream})
          allow(mock_stream).to receive(:write).and_raise(Errno::ECONNRESET)
          allow(mock_stream).to receive(:close)

          expect { transport.send(:monitor_streams) }.not_to raise_error
          expect(stream_registry.has_local_stream?(session_id)).to be false
        end
      end
    end

    describe "enhanced error handling in delivery methods" do
      before do
        stream_registry.register_stream(session_id, mock_stream)
      end

      describe "#deliver_to_session_stream" do
        it "closes stream on client disconnect" do
          allow(mock_stream).to receive(:write).and_raise(IOError)
          allow(mock_stream).to receive(:close)

          transport.send(:deliver_to_session_stream, session_id, {test: "data"})

          expect(stream_registry.has_local_stream?(session_id)).to be false
        end
      end

      describe "#deliver_to_active_streams" do
        it "closes disconnected streams during broadcast" do
          allow(mock_stream).to receive(:write).and_raise(Errno::EPIPE)
          allow(mock_stream).to receive(:close)

          transport.send(:deliver_to_active_streams, {test: "notification"})

          expect(stream_registry.has_local_stream?(session_id)).to be false
        end
      end
    end

    describe "#deliver_to_session_stream return value" do
      before do
        allow(mock_stream).to receive(:respond_to?).with(:closed?).and_return(true)
        allow(mock_stream).to receive(:respond_to?).with(:flush).and_return(true)
        allow(mock_stream).to receive(:closed?).and_return(false)
      end

      it "returns true when message is delivered successfully" do
        stream_registry.register_stream(session_id, mock_stream)
        allow(mock_stream).to receive(:write)
        allow(mock_stream).to receive(:flush)

        result = transport.send(:deliver_to_session_stream, session_id, {test: "data"})

        expect(result).to be true
      end

      it "returns false when stream is not found locally" do
        result = transport.send(:deliver_to_session_stream, "nonexistent-session", {test: "data"})

        expect(result).to be false
      end

      it "returns false when stream fails connection validation" do
        stream_registry.register_stream(session_id, mock_stream)
        allow(mock_stream).to receive(:closed?).and_return(true)
        allow(mock_stream).to receive(:close)

        result = transport.send(:deliver_to_session_stream, session_id, {test: "data"})

        expect(result).to be false
      end

      it "returns false when delivery raises network error" do
        stream_registry.register_stream(session_id, mock_stream)
        allow(mock_stream).to receive(:write).and_raise(Errno::EPIPE)
        allow(mock_stream).to receive(:close)

        result = transport.send(:deliver_to_session_stream, session_id, {test: "data"})

        expect(result).to be false
      end
    end
  end

  describe "#send_notification with session_id targeting" do
    let(:mock_stream) { StringIO.new }
    let(:target_session_id) { "target-session-456" }
    let(:other_session_id) { "other-session-789" }
    let(:other_stream) { StringIO.new }

    before do
      client_logger.connect_transport(transport)
    end

    context "when session_id is provided" do
      before do
        transport.instance_variable_get(:@stream_registry).register_stream(target_session_id, mock_stream)
        transport.instance_variable_get(:@stream_registry).register_stream(other_session_id, other_stream)
      end

      it "delivers notification only to the targeted stream" do
        transport.send_notification("notifications/progress", {progress: 50}, session_id: target_session_id)

        mock_stream.rewind
        other_stream.rewind

        target_output = mock_stream.read
        other_output = other_stream.read

        aggregate_failures do
          expect(target_output).to include("notifications/progress")
          expect(other_output).to be_empty
        end
      end

      it "queues notification if targeted stream delivery fails" do
        allow(mock_stream).to receive(:write).and_raise(IOError)
        allow(mock_stream).to receive(:close)

        transport.send_notification("notifications/progress", {progress: 50}, session_id: target_session_id)

        notification_queue = transport.instance_variable_get(:@notification_queue)
        expect(notification_queue.size).to eq(1)
      end

      it "queues notification if targeted stream does not exist" do
        transport.send_notification("notifications/progress", {progress: 50}, session_id: "nonexistent-session")

        notification_queue = transport.instance_variable_get(:@notification_queue)
        expect(notification_queue.size).to eq(1)
      end
    end

    context "when session_id is nil" do
      before do
        transport.instance_variable_get(:@stream_registry).register_stream(target_session_id, mock_stream)
        transport.instance_variable_get(:@stream_registry).register_stream(other_session_id, other_stream)
      end

      it "broadcasts to all active streams when no persistent notification stream exists" do
        transport.send_notification("notifications/message", {data: "broadcast"})

        mock_stream.rewind
        other_stream.rewind

        aggregate_failures do
          expect(mock_stream.read).to include("notifications/message")
          expect(other_stream.read).to include("notifications/message")
        end
      end
    end
  end

  describe "#handle_ping_response" do
    let(:server_request_store) { transport.instance_variable_get(:@server_request_store) }
    let(:ping_id) { "ping-abc123" }

    it "returns true and marks ping as completed for valid ping response" do
      server_request_store.register_request(ping_id, session_id, type: :ping)

      result = transport.send(:handle_ping_response, {"id" => ping_id, "result" => {}})

      aggregate_failures do
        expect(result).to be true
        expect(server_request_store.pending?(ping_id)).to be false
      end
    end

    it "returns false for response with no id" do
      result = transport.send(:handle_ping_response, {"result" => {}})

      expect(result).to be false
    end

    it "returns false for response id that is not a pending ping" do
      result = transport.send(:handle_ping_response, {"id" => "unknown-id", "result" => {}})

      expect(result).to be false
    end

    it "returns false for pending request that is not a ping type" do
      server_request_store.register_request("other-request", session_id, type: :other)

      result = transport.send(:handle_ping_response, {"id" => "other-request", "result" => {}})

      expect(result).to be false
    end

    it "handles errors gracefully and returns false" do
      allow(server_request_store).to receive(:pending?).and_raise(StandardError, "Redis error")

      result = transport.send(:handle_ping_response, {"id" => ping_id, "result" => {}})

      expect(result).to be false
    end
  end

  describe "#send_ping_to_stream" do
    let(:mock_stream) { double("stream") }
    let(:server_request_store) { transport.instance_variable_get(:@server_request_store) }
    let(:written_data) { [] }

    before do
      allow(mock_stream).to receive(:write) { |data| written_data << data }
      allow(mock_stream).to receive(:flush)
      allow(mock_stream).to receive(:respond_to?).with(:flush).and_return(true)
    end

    it "sends MCP-compliant ping request to stream" do
      transport.send(:send_ping_to_stream, mock_stream, session_id)

      # SSE format: first write is event ID, second is data
      data_line = written_data.find { |d| d.start_with?("data:") }

      aggregate_failures do
        expect(data_line).to include('"method":"ping"')
        expect(data_line).to include('"jsonrpc":"2.0"')
        expect(data_line).to match(/"id":"ping-[a-f0-9]+"/)
      end
    end

    it "registers ping request in server request store" do
      transport.send(:send_ping_to_stream, mock_stream, session_id)

      pending_requests = server_request_store.get_all_pending_requests
      expect(pending_requests.size).to eq(1)
      expect(pending_requests.first).to start_with("ping-")
    end

    it "associates ping with session_id" do
      transport.send(:send_ping_to_stream, mock_stream, session_id)

      pending_requests = server_request_store.get_all_pending_requests
      request_info = server_request_store.get_request(pending_requests.first)

      aggregate_failures do
        expect(request_info["session_id"]).to eq(session_id)
        expect(request_info["type"]).to eq("ping")
      end
    end
  end

  describe "ping timeout detection in monitor_streams" do
    let(:mock_stream) { double("stream") }
    let(:stream_registry) { transport.instance_variable_get(:@stream_registry) }
    let(:server_request_store) { transport.instance_variable_get(:@server_request_store) }

    before do
      allow(mock_stream).to receive(:write)
      allow(mock_stream).to receive(:flush)
      allow(mock_stream).to receive(:close)
      allow(mock_stream).to receive(:respond_to?).with(:flush).and_return(true)
      allow(mock_stream).to receive(:respond_to?).with(:closed?).and_return(true)
      allow(mock_stream).to receive(:closed?).and_return(false)

      stream_registry.register_stream(session_id, mock_stream)
    end

    it "closes streams with expired ping requests" do
      # Register an expired ping (created in the past)
      ping_id = "ping-expired"
      server_request_store.register_request(ping_id, session_id, type: :ping)

      # Simulate time passing by manipulating the request data
      request_key = "server_request:pending:#{ping_id}"
      request_data = JSON.parse(mock_redis.get(request_key))
      request_data["created_at"] = Time.now.to_f - 60 # 60 seconds ago
      mock_redis.set(request_key, request_data.to_json)

      transport.send(:monitor_streams)

      aggregate_failures do
        expect(stream_registry.has_local_stream?(session_id)).to be false
        expect(server_request_store.pending?(ping_id)).to be false
      end
    end

    it "keeps streams open when ping responses are received in time" do
      stream_registry.register_stream(session_id, mock_stream)

      # First monitor call sends ping
      transport.send(:monitor_streams)

      # Simulate receiving ping response
      pending_requests = server_request_store.get_all_pending_requests
      pending_requests.each do |request_id|
        server_request_store.mark_completed(request_id)
      end

      # Second monitor call should not close the stream
      transport.send(:monitor_streams)

      expect(stream_registry.has_local_stream?(session_id)).to be true
    end
  end

  describe "ping_timeout configuration" do
    it "uses default ping timeout of 10 seconds" do
      ping_timeout = transport.instance_variable_get(:@ping_timeout)
      expect(ping_timeout).to eq(10)
    end

    context "with custom ping_timeout" do
      let(:server) do
        ModelContextProtocol::Server.new do |config|
          config.name = "test-server"
          config.version = "1.0.0"
          config.registry = ModelContextProtocol::Server::Registry.new
          config.transport = {
            type: :streamable_http,
            require_sessions: false,
            validate_origin: false,
            ping_timeout: 30,
            env: rack_env
          }
        end
      end

      it "respects custom ping_timeout setting" do
        ping_timeout = transport.instance_variable_get(:@ping_timeout)
        expect(ping_timeout).to eq(30)
      end
    end
  end
end
