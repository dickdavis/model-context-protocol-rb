require "concurrent-ruby"

module ModelContextProtocol
  module Server::Progressable
    # Execute a block with automatic time-based progress reporting.
    # Uses Concurrent::TimerTask to send progress notifications at regular intervals.
    #
    # @param max_duration [Numeric] Expected duration in seconds
    # @param message [String, nil] Optional custom progress message
    # @yield block to execute with progress tracking
    # @return [Object] the result of the block
    #
    # @example
    #   progressable(max_duration: 30) do  # 30 seconds
    #     perform_long_operation
    #   end
    def progressable(max_duration:, message: nil, &block)
      context = Thread.current[:mcp_context]
      return yield unless context && context[:progress_token] && context[:transport]

      progress_token = context[:progress_token]
      transport = context[:transport]
      start_time = Time.now
      update_interval = [1.0, max_duration * 0.05].max

      timer_task = Concurrent::TimerTask.new(execution_interval: update_interval) do
        if context[:request_store] && context[:jsonrpc_request_id]
          break if context[:request_store].cancelled?(context[:jsonrpc_request_id])
        end

        elapsed_seconds = Time.now - start_time
        progress_pct = [(elapsed_seconds / max_duration) * 100, 99].min

        progress_message = if message
          "#{message} (#{elapsed_seconds.round(1)}s / ~#{max_duration}s)"
        else
          "Processing... (#{elapsed_seconds.round(1)}s / ~#{max_duration}s)"
        end

        begin
          transport.send_notification("notifications/progress", {
            progressToken: progress_token,
            progress: progress_pct.round(1),
            total: 100,
            message: progress_message
          })
        rescue
          break
        end

        timer_task.shutdown if elapsed_seconds >= max_duration
      end

      begin
        timer_task.execute

        result = yield

        begin
          transport.send_notification("notifications/progress", {
            progressToken: progress_token,
            progress: 100,
            total: 100,
            message: "Completed"
          })
        rescue
          nil
        end

        result
      ensure
        if timer_task&.running?
          timer_task.shutdown
          sleep(0.1) if timer_task.running?
        end
      end
    end
  end
end
