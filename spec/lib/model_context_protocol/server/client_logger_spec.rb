require "spec_helper"

RSpec.describe ModelContextProtocol::Server::ClientLogger do
  let(:transport) { double("transport") }
  let(:logger) { described_class.new(logger_name: "test-logger") }

  describe "#initialize" do
    it "creates a logger with default settings" do
      logger = described_class.new

      aggregate_failures do
        expect(logger.logger_name).to eq("server")
        expect(logger.level).to eq(Logger::INFO)
      end
    end

    it "accepts custom settings" do
      logger = described_class.new(logger_name: "custom", level: "debug")

      aggregate_failures do
        expect(logger.logger_name).to eq("custom")
        expect(logger.level).to eq(Logger::DEBUG)
      end
    end
  end

  describe "logging methods" do
    before do
      allow(transport).to receive(:send_notification)
      logger.connect_transport(transport)
    end

    describe "logging behavior" do
      it "sends debug messages when level is debug" do
        logger.level = Logger::DEBUG
        logger.debug("test message", key: "value")

        expect(transport).to have_received(:send_notification).with(
          "notifications/message",
          {
            level: "debug",
            logger: "test-logger",
            data: {message: "test message", key: "value"}
          }
        )
      end

      it "sends info messages" do
        logger.info("info message")

        expect(transport).to have_received(:send_notification).with(
          "notifications/message",
          {
            level: "info",
            logger: "test-logger",
            data: {message: "info message"}
          }
        )
      end

      it "sends warning messages" do
        logger.warn("warning message", error_code: 123)

        expect(transport).to have_received(:send_notification).with(
          "notifications/message",
          {
            level: "warning",
            logger: "test-logger",
            data: {message: "warning message", error_code: 123}
          }
        )
      end

      it "sends error messages" do
        logger.error("error message", backtrace: ["line1", "line2"])

        expect(transport).to have_received(:send_notification).with(
          "notifications/message",
          {
            level: "error",
            logger: "test-logger",
            data: {message: "error message", backtrace: ["line1", "line2"]}
          }
        )
      end

      it "sends fatal messages as critical" do
        logger.fatal("fatal error")

        expect(transport).to have_received(:send_notification).with(
          "notifications/message",
          {
            level: "critical",
            logger: "test-logger",
            data: {message: "fatal error"}
          }
        )
      end

      it "sends unknown messages as emergency" do
        logger.unknown("unknown message")

        expect(transport).to have_received(:send_notification).with(
          "notifications/message",
          {
            level: "emergency",
            logger: "test-logger",
            data: {message: "unknown message"}
          }
        )
      end

      it "accepts block form" do
        logger.info { "block message" }

        expect(transport).to have_received(:send_notification).with(
          "notifications/message",
          {
            level: "info",
            logger: "test-logger",
            data: {message: "block message"}
          }
        )
      end

      it "handles nil message with additional data" do
        logger.info(nil, key: "value")

        expect(transport).to have_received(:send_notification).with(
          "notifications/message",
          {
            level: "info",
            logger: "test-logger",
            data: {key: "value"}
          }
        )
      end
    end
  end

  describe "log level filtering" do
    before do
      allow(transport).to receive(:send_notification)
      logger.connect_transport(transport)
    end

    it "filters messages below the minimum level" do
      logger.level = Logger::WARN

      logger.debug("debug message")
      logger.info("info message")
      logger.warn("warn message")

      aggregate_failures do
        expect(transport).not_to have_received(:send_notification).with(
          "notifications/message", hash_including(level: "debug")
        )
        expect(transport).not_to have_received(:send_notification).with(
          "notifications/message", hash_including(level: "info")
        )
        expect(transport).to have_received(:send_notification).with(
          "notifications/message", hash_including(level: "warning")
        )
      end
    end
  end

  describe "#set_mcp_level" do
    it "maps MCP levels to Logger levels" do
      {
        "debug" => Logger::DEBUG,
        "info" => Logger::INFO,
        "notice" => Logger::INFO,
        "warning" => Logger::WARN,
        "error" => Logger::ERROR,
        "critical" => Logger::FATAL,
        "alert" => Logger::FATAL,
        "emergency" => Logger::UNKNOWN
      }.each do |mcp_level, logger_level|
        logger.set_mcp_level(mcp_level)
        expect(logger.level).to eq(logger_level)
      end
    end

    it "defaults to INFO for invalid levels" do
      logger.set_mcp_level("invalid")
      expect(logger.level).to eq(Logger::INFO)
    end
  end

  describe "#connect_transport" do
    it "sets the transport" do
      logger.connect_transport(transport)
      expect(logger.transport).to eq(transport)
    end

    context "with queued messages" do
      before do
        logger.info("queued message 1")
        logger.warn("queued message 2", key: "value")
      end

      it "flushes queued messages when transport connects" do
        allow(transport).to receive(:send_notification)

        logger.connect_transport(transport)

        aggregate_failures do
          expect(transport).to have_received(:send_notification).with(
            "notifications/message",
            {
              level: "info",
              logger: "test-logger",
              data: {message: "queued message 1"}
            }
          )

          expect(transport).to have_received(:send_notification).with(
            "notifications/message",
            {
              level: "warning",
              logger: "test-logger",
              data: {message: "queued message 2", key: "value"}
            }
          )
        end
      end
    end
  end

  describe "Ruby Logger compatibility" do
    it "delegates formatter methods" do
      logger.formatter = Logger::Formatter.new

      aggregate_failures do
        expect(logger).to respond_to(:datetime_format=)
        expect(logger).to respond_to(:progname)
        expect(logger).to respond_to(:progname=)
      end
    end

    it "supports level getter and setter" do
      logger.level = Logger::WARN
      expect(logger.level).to eq(Logger::WARN)
    end
  end
end
