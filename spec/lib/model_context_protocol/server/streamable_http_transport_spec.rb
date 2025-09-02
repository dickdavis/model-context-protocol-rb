require "spec_helper"

TestResponse = Data.define(:text) do
  def serialized
    {text:}
  end
end

RSpec.describe ModelContextProtocol::Server::StreamableHttpTransport do
  subject(:transport) do
    described_class.new(
      logger: logger,
      router: router,
      configuration: configuration
    )
  end

  let(:logger) { Logger.new(StringIO.new) }
  let(:router) { ModelContextProtocol::Server::Router.new(configuration: configuration) }
  let(:mock_redis) { MockRedis.new }
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

  describe "#handle_request" do
    context "when request and response objects are missing" do
      before do
        configuration.transport = {
          type: :streamable_http,
          redis_client: mock_redis
        }
      end

      it "raises ArgumentError" do
        expect { transport.handle_request }.to raise_error(
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
        let(:init_request) { {"method" => "initialize", "params" => {}} }

        before do
          mock_body.string = init_request.to_json
          mock_body.rewind
        end

        it "creates a session and returns response with session ID" do
          result = transport.handle_request

          aggregate_failures do
            expect(result[:json]).to include(text: "initialized")
            expect(result[:status]).to eq(200)
            expect(result[:headers]).to have_key("Mcp-Session-Id")

            session_id = result[:headers]["Mcp-Session-Id"]
            expect(session_id).to match(/\A[0-9a-f-]{36}\z/) # UUID format
          end
        end

        it "creates session in Redis" do
          result = transport.handle_request
          session_id = result[:headers]["Mcp-Session-Id"]

          expect(mock_redis.exists("session:#{session_id}")).to eq(1)
        end
      end

      context "for regular request without session" do
        let(:regular_request) { {"method" => "test_method", "params" => {}} }

        before do
          mock_body.string = regular_request.to_json
          mock_body.rewind
        end

        it "returns error for missing session ID" do
          result = transport.handle_request

          aggregate_failures do
            expect(result[:json]).to eq({error: "Invalid or missing session ID"})
            expect(result[:status]).to eq(400)
          end
        end
      end

      context "for regular request with valid session" do
        let(:regular_request) { {"method" => "ping", "params" => {}} }

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
          result = transport.handle_request

          aggregate_failures do
            expect(result[:json]).to include(text: "pong")
            expect(result[:status]).to eq(200)
          end
        end

        it "routes to stream when session has active stream" do
          mock_redis.hset("session:#{session_id}", "active_stream", true.to_json)

          result = transport.handle_request

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
          result = transport.handle_request

          aggregate_failures do
            expect(result[:json]).to eq({error: "Invalid JSON"})
            expect(result[:status]).to eq(400)
          end
        end
      end

      context "with internal error" do
        let(:error_request) { {"method" => "error_method", "params" => {}} }

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

          allow(logger).to receive(:error)
        end

        it "returns internal server error" do
          result = transport.handle_request

          aggregate_failures do
            expect(result[:json]).to eq({error: "Internal server error"})
            expect(result[:status]).to eq(500)
            expect(logger).to have_received(:error).with(/Error handling POST request/)
            expect(logger).to have_received(:error).with(kind_of(Array)) # backtrace
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
        result = transport.handle_request

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
        transport.handle_request

        stream_data = mock_redis.hget("session:#{session_id}", "active_stream")
        expect(JSON.parse(stream_data)).to be true
      end

      context "with invalid session" do
        before do
          allow(mock_request).to receive(:headers).and_return({"Mcp-Session-Id" => "invalid-session"})
        end

        it "returns error for invalid session" do
          result = transport.handle_request

          aggregate_failures do
            expect(result[:json]).to eq({error: "Invalid or missing session ID"})
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
        result = transport.handle_request

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
          result = transport.handle_request

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
        result = transport.handle_request

        aggregate_failures do
          expect(result[:json]).to eq({error: "Method not allowed"})
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
        result = transport.handle_request
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
        result = transport.handle_request
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

        result = transport.handle_request
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
        logger: logger,
        router: ModelContextProtocol::Server::Router.new(configuration: other_config),
        configuration: other_config
      )
    end

    it "routes messages between server instances via Redis" do
      mock_body.string = {"method" => "initialize"}.to_json
      mock_body.rewind
      allow(mock_request).to receive(:method).and_return("POST")
      allow(mock_request).to receive(:body).and_return(mock_body)
      allow(mock_request).to receive(:headers).and_return({})

      result = transport.handle_request
      session_id = result[:headers]["Mcp-Session-Id"]

      first_server_instance = transport.instance_variable_get(:@server_instance)
      session_store = transport.instance_variable_get(:@session_store)
      session_store.mark_stream_active(session_id, first_server_instance)

      other_router = other_server_transport.instance_variable_get(:@router)
      other_router.map("ping") do |message|
        TestResponse[text: "pong"]
      end

      other_mock_body = StringIO.new({"method" => "ping"}.to_json)
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

      result = other_server_transport.handle_request
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

      mock_body.string = {"method" => "initialize"}.to_json
      mock_body.rewind

      result = transport.handle_request
      session_id = result[:headers]["Mcp-Session-Id"]
      context_data = mock_redis.hget("session:#{session_id}", "context")
      parsed_context = JSON.parse(context_data)
      expect(parsed_context).to eq({"user_id" => "test-user", "app" => "test-app"})
    end

    it "handles session cleanup on DELETE" do
      mock_body.string = {"method" => "initialize"}.to_json
      mock_body.rewind

      result = transport.handle_request
      session_id = result[:headers]["Mcp-Session-Id"]

      expect(mock_redis.exists("session:#{session_id}")).to eq(1)

      allow(mock_request).to receive(:method).and_return("DELETE")
      allow(mock_request).to receive(:headers).and_return({"Mcp-Session-Id" => session_id})

      result = transport.handle_request

      aggregate_failures do
        expect(result[:json]).to eq({success: true})
        expect(result[:status]).to eq(200)
        expect(mock_redis.exists("session:#{session_id}")).to eq(0)
      end
    end
  end
end
