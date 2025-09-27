require "singleton"

module ModelContextProtocol
  module Server::GlobalConfig
    class ServerLogging
      include Singleton

      class NotConfiguredError < StandardError
        def initialize
          super("Server logging not configured. Call ModelContextProtocol::Server.configure_server_logging first")
        end
      end

      class LoggerConfig
        attr_accessor :logdev, :level, :formatter, :progname

        def initialize
          @level = Logger::INFO
          @progname = "MCP-Server"
        end

        def to_h
          {
            logdev: @logdev,
            level: @level,
            formatter: @formatter,
            progname: @progname
          }.compact
        end
      end

      def self.configure(&block)
        instance.configure(&block)
      end

      def self.configured?
        instance.configured?
      end

      def self.logger_params
        instance.logger_params
      end

      def self.reset!
        instance.reset!
      end

      def configure(&block)
        raise ArgumentError, "Configuration block required" unless block_given?

        @config = LoggerConfig.new
        yield(@config)
        @configured = true
      end

      def configured?
        @configured == true
      end

      def logger_params
        raise NotConfiguredError unless configured?

        @config.to_h
      end

      def reset!
        @configured = false
        @config = nil
      end

      private

      def initialize
        reset!
      end
    end
  end
end
