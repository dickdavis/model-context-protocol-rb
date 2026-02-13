# frozen_string_literal: true

require "puma/plugin"

Puma::Plugin.create do
  # Capture the DSL reference for deferred hook registration.
  def config(dsl)
    @dsl = dsl
  end

  # Register lifecycle hooks after configuration is finalized.
  # Using launcher.clustered? ensures reliable mode detection,
  # avoiding issues where config-time checks may not reflect
  # the final runtime worker count.
  def start(launcher)
    if (launcher.options[:workers] || 0) > 0
      @dsl.before_worker_boot { start_mcp_server }
      @dsl.before_worker_shutdown { shutdown_mcp_server }
    else
      launcher.events.after_booted { start_mcp_server }
      launcher.events.after_stopped { shutdown_mcp_server }
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
