require "spec_helper"

RSpec.describe ModelContextProtocol::Server::Progressable do
  let(:test_class) do
    Class.new do
      include ModelContextProtocol::Server::Progressable
      include ModelContextProtocol::Server::Cancellable
    end
  end

  let(:test_instance) { test_class.new }
  let(:transport) { double("transport") }
  let(:progress_token) { "test-progress-token-123" }

  before do
    allow(transport).to receive(:send_notification)
  end

  describe "#progressable" do
    context "when no MCP context is present" do
      it "executes the block normally without progress tracking" do
        result = test_instance.progressable(max_duration: 1) { "test result" }

        aggregate_failures do
          expect(result).to eq("test result")
          expect(transport).not_to have_received(:send_notification)
        end
      end
    end

    context "when MCP context is present but no progress token" do
      before do
        Thread.current[:mcp_context] = {
          jsonrpc_request_id: "123",
          transport: transport
        }
      end

      after do
        Thread.current[:mcp_context] = nil
      end

      it "executes the block normally without progress tracking" do
        result = test_instance.progressable(max_duration: 1) { "test result" }

        aggregate_failures do
          expect(result).to eq("test result")
          expect(transport).not_to have_received(:send_notification)
        end
      end
    end

    context "when MCP context is present but no transport" do
      before do
        Thread.current[:mcp_context] = {
          jsonrpc_request_id: "123",
          progress_token: progress_token
        }
      end

      after do
        Thread.current[:mcp_context] = nil
      end

      it "executes the block normally without progress tracking" do
        result = test_instance.progressable(max_duration: 1) { "test result" }
        expect(result).to eq("test result")
      end
    end

    context "when full MCP context with progress token is present" do
      before do
        Thread.current[:mcp_context] = {
          jsonrpc_request_id: "123",
          progress_token: progress_token,
          transport: transport
        }
      end

      after do
        Thread.current[:mcp_context] = nil
      end

      it "executes the block and sends progress notifications" do
        result = test_instance.progressable(max_duration: 0.5) do
          sleep 0.1
          "test result"
        end

        aggregate_failures do
          expect(result).to eq("test result")
          expect(transport).to have_received(:send_notification).with(
            "notifications/progress",
            hash_including(
              progressToken: progress_token,
              progress: 100,
              total: 100,
              message: "Completed"
            ),
            hash_including(session_id: nil)
          )
        end
      end

      it "sends progress notifications with custom message" do
        custom_message = "Processing data"

        result = test_instance.progressable(max_duration: 0.5, message: custom_message) do
          sleep 0.1
          "test result"
        end

        aggregate_failures do
          expect(result).to eq("test result")
          expect(transport).to have_received(:send_notification).with(
            "notifications/progress",
            hash_including(
              progressToken: progress_token,
              progress: 100,
              total: 100,
              message: "Completed"
            ),
            hash_including(session_id: nil)
          )
        end
      end

      it "handles exceptions in the block gracefully" do
        expect {
          test_instance.progressable(max_duration: 0.5) do
            raise StandardError, "test error"
          end
        }.to raise_error(StandardError, "test error")
      end

      it "handles notification send errors gracefully" do
        allow(transport).to receive(:send_notification).and_raise(IOError, "connection broken")

        result = test_instance.progressable(max_duration: 0.5) do
          sleep 0.1
          "test result"
        end

        expect(result).to eq("test result")
      end

      it "calculates progress percentage correctly" do
        test_instance.progressable(max_duration: 0.5) do
          sleep 0.1
          "done"
        end

        expect(transport).to have_received(:send_notification).with(
          "notifications/progress",
          hash_including(
            progressToken: progress_token,
            progress: 100,
            total: 100,
            message: "Completed"
          ),
          hash_including(session_id: nil)
        )
      end
    end

    context "when stream_id is present in MCP context" do
      let(:stream_id) { "test-stream-abc123" }

      before do
        Thread.current[:mcp_context] = {
          jsonrpc_request_id: "123",
          progress_token: progress_token,
          transport: transport,
          stream_id: stream_id
        }
      end

      after do
        Thread.current[:mcp_context] = nil
      end

      it "sends progress notifications targeted to the specific stream" do
        test_instance.progressable(max_duration: 0.5) do
          sleep 0.1
          "result"
        end

        expect(transport).to have_received(:send_notification).with(
          "notifications/progress",
          hash_including(
            progressToken: progress_token,
            progress: 100,
            total: 100,
            message: "Completed"
          ),
          session_id: stream_id
        )
      end

      it "includes stream_id in intermediate progress notifications" do
        test_instance.progressable(max_duration: 0.3) do
          sleep 0.2
          "result"
        end

        expect(transport).to have_received(:send_notification).with(
          "notifications/progress",
          hash_including(progressToken: progress_token),
          session_id: stream_id
        ).at_least(:once)
      end
    end

    context "with very short max_duration" do
      before do
        Thread.current[:mcp_context] = {
          jsonrpc_request_id: "123",
          progress_token: progress_token,
          transport: transport
        }
      end

      after do
        Thread.current[:mcp_context] = nil
      end

      it "still works with sub-second durations" do
        result = test_instance.progressable(max_duration: 0.1) do
          "quick result"
        end

        expect(result).to eq("quick result")

        expect(transport).to have_received(:send_notification).with(
          "notifications/progress",
          hash_including(progress: 100, message: "Completed"),
          hash_including(session_id: nil)
        )
      end
    end
  end

  describe "progressable with cancellable" do
    let(:request_store) { double("request_store") }

    before do
      Thread.current[:mcp_context] = {
        jsonrpc_request_id: "123",
        progress_token: progress_token,
        transport: transport,
        request_store: request_store
      }

      allow(request_store).to receive(:cancelled?).with("123").and_return(false)
    end

    after do
      Thread.current[:mcp_context] = nil
    end

    it "combines progress tracking with cancellation support" do
      result = test_instance.progressable(max_duration: 0.5) do
        test_instance.cancellable do
          sleep 0.1
          "combined result"
        end
      end

      aggregate_failures do
        expect(result).to eq("combined result")
        expect(transport).to have_received(:send_notification).with(
          "notifications/progress",
          hash_including(
            progressToken: progress_token,
            progress: 100,
            message: "Completed"
          ),
          hash_including(session_id: nil)
        )
      end
    end

    it "handles cancellation during progressive execution" do
      allow(request_store).to receive(:cancelled?).with("123").and_return(false, true)

      expect {
        test_instance.progressable(max_duration: 1) do
          test_instance.cancellable(interval: 0.1) do
            sleep 0.3
            "should not complete"
          end
        end
      }.to raise_error(ModelContextProtocol::Server::Cancellable::CancellationError)
    end
  end

  describe "timer cleanup" do
    before do
      Thread.current[:mcp_context] = {
        jsonrpc_request_id: "123",
        progress_token: progress_token,
        transport: transport
      }
    end

    after do
      Thread.current[:mcp_context] = nil
    end

    it "properly cleans up timer tasks on completion" do
      initial_thread_count = Thread.list.size

      test_instance.progressable(max_duration: 0.2) do
        sleep 0.05
        "result"
      end

      sleep 0.1

      final_thread_count = Thread.list.size
      expect(final_thread_count).to be <= initial_thread_count
    end

    it "cleans up timer tasks even when block raises an exception" do
      initial_thread_count = Thread.list.size

      expect {
        test_instance.progressable(max_duration: 0.2) do
          sleep 0.05
          raise "test error"
        end
      }.to raise_error("test error")

      sleep 0.1

      final_thread_count = Thread.list.size
      expect(final_thread_count).to be <= initial_thread_count + 1
    end
  end

  describe "timer cancellation" do
    let(:request_store) { double("request_store") }

    before do
      Thread.current[:mcp_context] = {
        jsonrpc_request_id: "test-request-123",
        progress_token: progress_token,
        transport: transport,
        request_store: request_store
      }
    end

    after do
      Thread.current[:mcp_context] = nil
    end

    context "when request is cancelled during execution" do
      it "stops timer immediately when request is marked as cancelled" do
        allow(request_store).to receive(:cancelled?).with("test-request-123").and_return(false, false, true)

        start_time = Time.now
        result = test_instance.progressable(max_duration: 5) do
          sleep 0.3
          "completed"
        end
        end_time = Time.now

        aggregate_failures do
          expect(result).to eq("completed")
          expect(end_time - start_time).to be < 5
          expect(transport).to have_received(:send_notification).with(
            "notifications/progress",
            hash_including(progress: 100, message: "Completed"),
            hash_including(session_id: nil)
          )
        end
      end

      it "prevents timer from running when request is already cancelled" do
        allow(request_store).to receive(:cancelled?).with("test-request-123").and_return(true)

        result = test_instance.progressable(max_duration: 1) do
          sleep 0.1
          "completed despite cancellation"
        end

        aggregate_failures do
          expect(result).to eq("completed despite cancellation")
          expect(transport).to have_received(:send_notification).with(
            "notifications/progress",
            hash_including(progress: 100, message: "Completed"),
            hash_including(session_id: nil)
          )
        end
      end
    end

    context "when transport fails during progress notifications" do
      it "stops timer when transport send_notification raises an error" do
        call_count = 0
        allow(transport).to receive(:send_notification) do |method, data|
          call_count += 1
          if method == "notifications/progress" && data[:progress] != 100
            raise IOError, "Transport connection broken"
          end
        end
        allow(request_store).to receive(:cancelled?).and_return(false)

        result = test_instance.progressable(max_duration: 2) do
          sleep 0.2
          "completed"
        end

        aggregate_failures do
          expect(result).to eq("completed")
          expect(transport).to have_received(:send_notification).with(
            "notifications/progress",
            hash_including(progress: 100, message: "Completed"),
            hash_including(session_id: nil)
          )
        end
      end
    end

    context "thread cleanup with cancellation support" do
      it "properly cleans up timer threads even when request store is present" do
        allow(request_store).to receive(:cancelled?).and_return(false)
        initial_thread_count = Thread.list.size

        test_instance.progressable(max_duration: 0.2) do
          sleep 0.05
          "result"
        end

        sleep 0.1

        final_thread_count = Thread.list.size
        expect(final_thread_count).to be <= initial_thread_count
      end

      it "handles missing request_store gracefully" do
        Thread.current[:mcp_context] = {
          jsonrpc_request_id: "test-request-123",
          progress_token: progress_token,
          transport: transport
        }

        result = test_instance.progressable(max_duration: 0.1) do
          "works without request_store"
        end

        expect(result).to eq("works without request_store")
      end
    end

    context "when HTTP request terminates silently (no explicit cancellation)" do
      it "eventually stops timer when transport succeeds but request is dead" do
        allow(request_store).to receive(:cancelled?).and_return(false)
        allow(transport).to receive(:send_notification).and_return(true)

        initial_thread_count = Thread.list.size

        result = test_instance.progressable(max_duration: 1) do
          sleep 0.1
          "completed"
        end

        sleep 0.3

        final_thread_count = Thread.list.size

        aggregate_failures do
          expect(result).to eq("completed")
          expect(final_thread_count).to be <= initial_thread_count
          expect(transport).to have_received(:send_notification).at_least(:once)
        end
      end

      it "timer auto-shuts down after max_duration even without cancellation" do
        allow(request_store).to receive(:cancelled?).and_return(false)
        allow(transport).to receive(:send_notification).and_return(true)

        start_time = Time.now

        result = test_instance.progressable(max_duration: 0.2) do
          sleep 0.5
          "should complete despite timer timeout"
        end

        end_time = Time.now

        aggregate_failures do
          expect(result).to eq("should complete despite timer timeout")
          expect(end_time - start_time).to be >= 0.2
        end
      end
    end
  end
end
