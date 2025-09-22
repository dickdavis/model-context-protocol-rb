require "spec_helper"

RSpec.describe ModelContextProtocol::Server::Cancellable do
  let(:test_class) do
    Class.new do
      include ModelContextProtocol::Server::Cancellable
    end
  end

  let(:instance) { test_class.new }

  describe "#cancellable" do
    let(:request_store) { double("request_store") }
    let(:request_id) { "test-request-123" }

    before do
      Thread.current[:mcp_context] = {
        request_id: request_id,
        request_store: request_store
      }
    end

    after do
      Thread.current[:mcp_context] = nil
    end

    context "when request is not cancelled" do
      before do
        allow(request_store).to receive(:cancelled?).with(request_id).and_return(false)
      end

      it "executes the block successfully" do
        result = instance.cancellable do
          "success"
        end

        expect(result).to eq("success")
      end

      it "returns the block result" do
        result = instance.cancellable do
          {data: "test", count: 42}
        end

        expect(result).to eq({data: "test", count: 42})
      end

      it "passes through exceptions from the block" do
        expect {
          instance.cancellable do
            raise StandardError, "block error"
          end
        }.to raise_error(StandardError, "block error")
      end
    end

    context "when request is cancelled before execution" do
      before do
        allow(request_store).to receive(:cancelled?).with(request_id).and_return(true)
      end

      it "raises CancellationError before executing the block" do
        block_executed = false

        expect {
          instance.cancellable do
            block_executed = true
            "should not execute"
          end
        }.to raise_error(ModelContextProtocol::Server::Cancellable::CancellationError)

        expect(block_executed).to be false
      end
    end

    context "when request is cancelled during execution" do
      it "interrupts a sleeping operation" do
        call_count = 0
        allow(request_store).to receive(:cancelled?).with(request_id) do
          call_count += 1
          call_count > 1
        end

        start_time = Time.now

        expect {
          instance.cancellable(interval: 0.1) do
            sleep 1.0
            "should not complete"
          end
        }.to raise_error(ModelContextProtocol::Server::Cancellable::CancellationError)

        elapsed = Time.now - start_time

        expect(elapsed).to be < 0.5
      end

      it "interrupts a long-running computation" do
        call_count = 0
        allow(request_store).to receive(:cancelled?).with(request_id) do
          call_count += 1
          call_count > 1
        end

        iterations = 0

        expect {
          instance.cancellable(interval: 0.05) do
            10000.times do |i|
              iterations = i
              sleep 0.01 if i % 100 == 0
            end
            "completed"
          end
        }.to raise_error(ModelContextProtocol::Server::Cancellable::CancellationError)

        expect(iterations).to be < 10000
      end
    end

    context "with custom polling interval" do
      it "respects the custom interval" do
        allow(request_store).to receive(:cancelled?).with(request_id).and_return(false)

        mock_timer = double("timer", execute: nil, shutdown: nil, running?: false)
        expect(Concurrent::TimerTask).to receive(:new).with(execution_interval: 0.05).and_return(mock_timer)

        instance.cancellable(interval: 0.05) do
          "test"
        end
      end
    end

    context "when no context is available" do
      before do
        Thread.current[:mcp_context] = nil
      end

      it "executes the block without cancellation support" do
        result = instance.cancellable do
          "no context"
        end

        expect(result).to eq("no context")
      end
    end

    context "resource cleanup" do
      it "does not shutdown timer when not running" do
        allow(request_store).to receive(:cancelled?).with(request_id).and_return(false)

        mock_timer = double("timer", execute: nil, running?: false)
        expect(mock_timer).not_to receive(:shutdown)
        allow(Concurrent::TimerTask).to receive(:new).and_return(mock_timer)

        instance.cancellable do
          "completed"
        end
      end

      it "shuts down running timer when block raises an exception" do
        allow(request_store).to receive(:cancelled?).with(request_id).and_return(false)

        mock_timer = double("timer", execute: nil, running?: true)
        expect(mock_timer).to receive(:shutdown)
        allow(Concurrent::TimerTask).to receive(:new).and_return(mock_timer)

        expect {
          instance.cancellable do
            raise StandardError, "test error"
          end
        }.to raise_error(StandardError, "test error")
      end

      it "shuts down running timer when block completes normally" do
        allow(request_store).to receive(:cancelled?).with(request_id).and_return(false)

        mock_timer = double("timer", execute: nil, running?: true)
        expect(mock_timer).to receive(:shutdown)
        allow(Concurrent::TimerTask).to receive(:new).and_return(mock_timer)

        instance.cancellable do
          "completed"
        end
      end
    end
  end
end
