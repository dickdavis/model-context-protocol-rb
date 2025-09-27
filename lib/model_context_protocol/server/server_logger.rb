require "logger"
require "json"

module ModelContextProtocol
  class Server::ServerLogger < Logger
    class StdoutNotAllowedError < StandardError; end

    attr_reader :logdev

    def initialize(logdev: $stderr, level: Logger::INFO, formatter: nil, progname: "MCP-Server")
      super(logdev)
      @logdev = logdev

      self.level = level
      self.progname = progname

      self.formatter = formatter || proc do |severity, datetime, progname, msg|
        timestamp = datetime.strftime("%Y-%m-%d %H:%M:%S.%3N")
        prog_name = progname ? "[#{progname}]" : ""
        mcp_context = Thread.current[:mcp_context]
        request_id = mcp_context&.dig(:jsonrpc_request_id)
        request_id_str = request_id ? " [#{request_id}]" : ""

        "[#{timestamp}] #{prog_name}#{request_id_str} #{severity}: #{msg}\n"
      end
    end
  end
end
