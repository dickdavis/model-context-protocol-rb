require "spec_helper"

TestResponse = Data.define(:text) do
  def serialized
    {text:}
  end
end

RSpec.describe ModelContextProtocol::Server::StreamableHttpTransport do
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
      redis_client: mock_redis
    }
    config
  end

  let(:mock_request) { double("request") }
  let(:mock_response) { double("response") }
  let(:mock_body) { StringIO.new }
  let(:session_id) { "test-session-123" }

  before do
    mock_redis.flushdb

    allow(mock_redis).to receive(:publish)
    allow(mock_redis).to receive(:subscribe).and_yield(double("on").tap do |on|
      allow(on).to receive(:message).and_yield("channel", '{"session_id":"test","message":"data"}')
    end)

    router.map("initialize") do |message|
      TestResponse[text: "initialized"]
    end

    router.map("ping") do |message|
      TestResponse[text: "pong"]
    end

    router.map("error_method") do |message|
      raise "Something went wrong"
    end

    configuration.transport = {
      type: :streamable_http,
      redis_client: mock_redis,
      request: mock_request,
      response: mock_response
    }
  end

  describe "#handle" do
    context "when request and response objects are missing" do
      before do
        configuration.transport = {
          type: :streamable_http,
          redis_client: mock_redis
        }
      end

      it "raises ArgumentError" do
        expect { transport.handle }.to raise_error(
          ArgumentError,
          "StreamableHTTP transport requires request and response objects in transport_options"
        )
      end
    end

    context "with POST request" do
      before do
        allow(mock_request).to receive(:method).and_return("POST")
        allow(mock_request).to receive(:body).and_return(mock_body)
        allow(mock_request).to receive(:headers).and_return({})
      end

      context "for initialization request" do
        let(:init_request) { {"method" => "initialize", "params" => {}, "id" => "init-1"} }

        before do
          mock_body.string = init_request.to_json
          mock_body.rewind
        end

        it "creates a session and returns response with session ID" do
          result = transport.handle

          aggregate_failures do
            expect(result[:json]).to eq({
              jsonrpc: "2.0",
              id: "init-1",
              result: {text: "initialized"}
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

      context "for regular request without session" do
        let(:regular_request) { {"method" => "test_method", "params" => {}, "id" => "req-1"} }

        before do
          mock_body.string = regular_request.to_json
          mock_body.rewind
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

      context "for regular request with valid session" do
        let(:regular_request) { {"method" => "ping", "params" => {}, "id" => "ping-1"} }

        before do
          mock_body.string = regular_request.to_json
          mock_body.rewind

          mock_redis.hset("session:#{session_id}", {
            "id" => session_id.to_json,
            "server_instance" => "test-server".to_json,
            "context" => {}.to_json,
            "created_at" => Time.now.to_f.to_json,
            "last_activity" => Time.now.to_f.to_json,
            "active_stream" => false.to_json
          })

          allow(mock_request).to receive(:headers).and_return({"Mcp-Session-Id" => session_id})
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
          mock_body.string = "invalid json"
          mock_body.rewind
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

      context "with internal error" do
        let(:error_request) { {"method" => "error_method", "params" => {}, "id" => "error-1"} }

        before do
          mock_body.string = error_request.to_json
          mock_body.rewind
          allow(mock_request).to receive(:headers).and_return({"Mcp-Session-Id" => session_id})

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
        allow(mock_request).to receive(:method).and_return("GET")
        allow(mock_request).to receive(:headers).and_return({"Mcp-Session-Id" => session_id})

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

      it "marks session as having active stream" do
        transport.handle

        stream_data = mock_redis.hget("session:#{session_id}", "active_stream")
        expect(JSON.parse(stream_data)).to be true
      end

      context "with invalid session" do
        before do
          allow(mock_request).to receive(:headers).and_return({"Mcp-Session-Id" => "invalid-session"})
        end

        it "returns error for invalid session" do
          result = transport.handle

          aggregate_failures do
            expect(result[:json]).to eq({
              jsonrpc: "2.0",
              id: nil,
              error: {code: -32600, message: "Invalid or missing session ID"}
            })
            expect(result[:status]).to eq(400)
          end
        end
      end
    end

    context "with DELETE request" do
      before do
        allow(mock_request).to receive(:method).and_return("DELETE")
        allow(mock_request).to receive(:headers).and_return({"Mcp-Session-Id" => session_id})

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
          allow(mock_request).to receive(:headers).and_return({})
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
        allow(mock_request).to receive(:method).and_return("PUT")
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
      allow(mock_request).to receive(:method).and_return("GET")
      allow(mock_request).to receive(:headers).and_return({"Mcp-Session-Id" => session_id})

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
        expect(JSON.parse(stream_data)).to be false # Should be cleaned up
      end
    end

    describe "keep-alive functionality" do
      before do
        allow(mock_stream).to receive(:write)
        allow(mock_stream).to receive(:flush)
        allow(mock_stream).to receive(:respond_to?).with(:flush).and_return(true)
      end

      it "sends ping messages to detect connection status" do
        result = transport.handle
        stream_proc = result[:stream_proc]

        expect(mock_stream).to receive(:write).with(": ping\n\n")
        expect(mock_stream).to receive(:flush)

        stream_thread = Thread.new do
          stream_proc.call(mock_stream)
        rescue
        end

        sleep 0.1
        stream_thread.kill if stream_thread.alive?
        stream_thread.join
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
        redis_client: mock_redis
      }

      allow(mock_redis).to receive(:publish)
      allow(mock_redis).to receive(:subscribe)

      described_class.new(
        router: ModelContextProtocol::Server::Router.new(configuration: other_config),
        configuration: other_config
      )
    end

    it "routes messages between server instances via Redis" do
      mock_body.string = {"method" => "initialize", "id" => "init-1"}.to_json
      mock_body.rewind
      allow(mock_request).to receive(:method).and_return("POST")
      allow(mock_request).to receive(:body).and_return(mock_body)
      allow(mock_request).to receive(:headers).and_return({})

      result = transport.handle
      session_id = result[:headers]["Mcp-Session-Id"]

      first_server_instance = transport.instance_variable_get(:@server_instance)
      session_store = transport.instance_variable_get(:@session_store)
      session_store.mark_stream_active(session_id, first_server_instance)

      other_router = other_server_transport.instance_variable_get(:@router)
      other_router.map("ping") do |message|
        TestResponse[text: "pong"]
      end

      other_mock_body = StringIO.new({"method" => "ping", "id" => "ping-1"}.to_json)
      other_mock_request = double("other_request")
      allow(other_mock_request).to receive(:method).and_return("POST")
      allow(other_mock_request).to receive(:body).and_return(other_mock_body)
      allow(other_mock_request).to receive(:headers).and_return({"Mcp-Session-Id" => session_id})

      other_config = other_server_transport.instance_variable_get(:@configuration)
      other_config.transport = {
        type: :streamable_http,
        redis_client: mock_redis,
        request: other_mock_request,
        response: mock_response
      }

      expect(mock_redis).to receive(:publish)

      result = other_server_transport.handle
      expect(result[:json]).to eq({accepted: true})
    end
  end

  describe "session management integration" do
    before do
      allow(mock_request).to receive(:method).and_return("POST")
      allow(mock_request).to receive(:body).and_return(mock_body)
      allow(mock_request).to receive(:headers).and_return({})
    end

    it "creates sessions with server context" do
      configuration.context = {user_id: "test-user", app: "test-app"}

      mock_body.string = {"method" => "initialize", "id" => "init-1"}.to_json
      mock_body.rewind

      result = transport.handle
      session_id = result[:headers]["Mcp-Session-Id"]
      context_data = mock_redis.hget("session:#{session_id}", "context")
      parsed_context = JSON.parse(context_data)
      expect(parsed_context).to eq({"user_id" => "test-user", "app" => "test-app"})
    end

    it "handles session cleanup on DELETE" do
      mock_body.string = {"method" => "initialize", "id" => "init-1"}.to_json
      mock_body.rewind

      result = transport.handle
      session_id = result[:headers]["Mcp-Session-Id"]

      expect(mock_redis.exists("session:#{session_id}")).to eq(1)

      allow(mock_request).to receive(:method).and_return("DELETE")
      allow(mock_request).to receive(:headers).and_return({"Mcp-Session-Id" => session_id})

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
      allow(mock_request).to receive(:method).and_return("GET")
      allow(mock_request).to receive(:headers).and_return({})
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
          transport.instance_variable_get(:@local_streams)[session_id] = mock_stream
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
          notification = JSON.parse(output.gsub("data: ", "").strip)

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

          queued_notification = notification_queue.first
          aggregate_failures do
            expect(queued_notification[:jsonrpc]).to eq("2.0")
            expect(queued_notification[:method]).to eq("notifications/message")
            expect(queued_notification[:params][:level]).to eq("warning")
            expect(queued_notification[:params][:data][:message]).to eq("queued notification")
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
          notification = JSON.parse(output.gsub("data: ", "").strip)
          expect(notification["params"]["data"]["message"]).to eq("queued message")
        end
      end
    end

    describe "logging error handling" do
      let(:test_stream) { StringIO.new }

      before do
        allow(mock_request).to receive(:method).and_return("POST")
        allow(mock_request).to receive(:headers).and_return({})
        allow(mock_request).to receive(:body).and_return(mock_body)
      end

      it "uses MCP logger for keepalive thread errors" do
        allow(mcp_logger).to receive(:error)

        original_sleep = method(:sleep)
        allow(transport).to receive(:sleep) do |duration|
          raise StandardError, "keepalive error" if duration == 30
          original_sleep.call(duration) if duration < 30
        end

        transport.send(:start_keepalive_thread, "session-id", test_stream)

        sleep(0.01)

        expect(mcp_logger).to have_received(:error).with("Keepalive thread error", error: "keepalive error")
      end

      it "uses MCP logger for Redis subscriber errors" do
        allow(mcp_logger).to receive(:error)
        allow(mock_redis).to receive(:subscribe).and_raise(StandardError, "redis error")

        transport.send(:setup_redis_subscriber)

        sleep(0.01)

        expect(mcp_logger).to have_received(:error).at_least(1).times.with("Redis subscriber error",
          error: "redis error",
          backtrace: kind_of(Array))
      end
    end
  end
end
