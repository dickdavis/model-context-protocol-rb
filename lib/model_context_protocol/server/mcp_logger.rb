require "logger"
require "forwardable"
require "json"

module ModelContextProtocol
  class Server::MCPLogger
    extend Forwardable

    def_delegators :@internal_logger, :datetime_format=, :formatter=, :progname, :progname=

    LEVEL_MAP = {
      "debug" => Logger::DEBUG,
      "info" => Logger::INFO,
      "notice" => Logger::INFO,
      "warning" => Logger::WARN,
      "error" => Logger::ERROR,
      "critical" => Logger::FATAL,
      "alert" => Logger::FATAL,
      "emergency" => Logger::UNKNOWN
    }.freeze

    REVERSE_LEVEL_MAP = {
      Logger::DEBUG => "debug",
      Logger::INFO => "info",
      Logger::WARN => "warning",
      Logger::ERROR => "error",
      Logger::FATAL => "critical",
      Logger::UNKNOWN => "emergency"
    }.freeze

    attr_accessor :transport
    attr_reader :logger_name, :enabled

    def initialize(logger_name: "server", level: "info", enabled: true)
      @logger_name = logger_name
      @enabled = enabled
      @internal_logger = Logger.new(nil)
      @internal_logger.level = LEVEL_MAP[level] || Logger::INFO
      @transport = nil
      @queued_messages = []
    end

    %i[debug info warn error fatal unknown].each do |severity|
      define_method(severity) do |message = nil, **data, &block|
        return true unless @enabled
        add(Logger.const_get(severity.to_s.upcase), message, data, &block)
      end
    end

    def add(severity, message = nil, data = {}, &block)
      return true unless @enabled
      return true if severity < @internal_logger.level

      message = block.call if message.nil? && block_given?
      send_notification(severity, message, data)
      true
    end

    def level=(value)
      @internal_logger.level = value
    end

    def level
      @internal_logger.level
    end

    def set_mcp_level(mcp_level)
      self.level = LEVEL_MAP[mcp_level] || Logger::INFO
    end

    def connect_transport(transport)
      @transport = transport
      flush_queued_messages if @enabled
    end

    private

    def send_notification(severity, message, data)
      return unless @enabled

      notification_params = {
        level: REVERSE_LEVEL_MAP[severity] || "info",
        logger: @logger_name,
        data: format_data(message, data)
      }

      if @transport
        @transport.send_notification("notifications/message", notification_params)
      else
        @queued_messages << notification_params
      end
    end

    def format_data(message, additional_data)
      data = {}
      data[:message] = message.to_s if message
      data.merge!(additional_data) unless additional_data.empty?
      data
    end

    def flush_queued_messages
      return unless @transport && @enabled
      @queued_messages.each do |params|
        @transport.send_notification("notifications/message", params)
      end
      @queued_messages.clear
    end
  end
end
