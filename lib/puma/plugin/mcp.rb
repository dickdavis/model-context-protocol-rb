# frozen_string_literal: true

require "puma/plugin"

Puma::Plugin.create do
  # Configure Puma hooks to manage MCP server lifecycle
  # Handles both clustered mode (workers > 0) and single mode (workers = 0)
  def config(dsl)
    if dsl.get(:workers, 0).to_i.positive?
      # Clustered mode: each worker starts after forking
      dsl.before_worker_boot { start_mcp_server }
      dsl.before_worker_shutdown { shutdown_mcp_server }
    else
      # Single mode: start after server boots (no forking)
      dsl.after_booted { start_mcp_server }
      dsl.after_stopped { shutdown_mcp_server }
    end
  end

  private

  def start_mcp_server
    return unless ModelContextProtocol::Server.configured?
    return if ModelContextProtocol::Server.running?

    ModelContextProtocol::Server.start
  end

  def shutdown_mcp_server
    return unless ModelContextProtocol::Server.running?

    ModelContextProtocol::Server.shutdown
  end
end
