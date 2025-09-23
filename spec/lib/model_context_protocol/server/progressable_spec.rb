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
          request_id: "123",
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
          request_id: "123",
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
          request_id: "123",
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
            )
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
            )
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
          )
        )
      end
    end

    context "with very short max_duration" do
      before do
        Thread.current[:mcp_context] = {
          request_id: "123",
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
          hash_including(progress: 100, message: "Completed")
        )
      end
    end
  end

  describe "progressable with cancellable" do
    let(:request_store) { double("request_store") }

    before do
      Thread.current[:mcp_context] = {
        request_id: "123",
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
          )
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
        request_id: "123",
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
end
