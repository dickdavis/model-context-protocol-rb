require "spec_helper"
require "tempfile"

RSpec.describe ModelContextProtocol::Server::ServerLogger do
  subject(:logger_class) { described_class }

  describe "initialization" do
    context "with default settings" do
      it "creates a logger with default stderr output" do
        logger = logger_class.new

        aggregate_failures do
          expect(logger.logdev).to eq($stderr)
          expect(logger.level).to eq(Logger::INFO)
          expect(logger.progname).to eq("MCP-Server")
        end
      end
    end

    context "with custom settings" do
      it "accepts custom logdev parameter" do
        logger = logger_class.new(logdev: $stderr)

        expect(logger.logdev).to eq($stderr)
      end

      it "accepts custom level parameter" do
        logger = logger_class.new(level: Logger::DEBUG)

        expect(logger.level).to eq(Logger::DEBUG)
      end

      it "accepts custom progname parameter" do
        logger = logger_class.new(progname: "TestServer")

        expect(logger.progname).to eq("TestServer")
      end

      it "accepts custom output destination" do
        tempfile = Tempfile.new("test_log")
        logger = logger_class.new(logdev: tempfile)

        expect(logger.logdev).to eq(tempfile)

        tempfile.close
        tempfile.unlink
      end

      it "accepts custom formatter" do
        formatter = proc { |severity, datetime, progname, msg| "#{severity}: #{msg}\n" }
        logger = logger_class.new(formatter: formatter)

        expect(logger.formatter).to eq(formatter)
      end

      it "accepts all parameters together" do
        tempfile = Tempfile.new("test_all")
        formatter = proc { |severity, datetime, progname, msg| "CUSTOM: #{msg}\n" }

        logger = logger_class.new(
          logdev: tempfile,
          level: Logger::WARN,
          formatter: formatter,
          progname: "AllParamsTest"
        )

        aggregate_failures do
          expect(logger.logdev).to eq(tempfile)
          expect(logger.level).to eq(Logger::WARN)
          expect(logger.formatter).to eq(formatter)
          expect(logger.progname).to eq("AllParamsTest")
        end

        tempfile.close
        tempfile.unlink
      end
    end
  end

  describe "logging functionality" do
    it "logs messages with default formatter" do
      output = StringIO.new
      logger = logger_class.new(logdev: output)

      logger.info("Test message")

      output.rewind
      log_output = output.read
      expect(log_output).to match(/\[MCP-Server\] INFO: Test message/)
    end

    it "logs messages with custom formatter" do
      output = StringIO.new
      formatter = proc { |severity, datetime, progname, msg| "CUSTOM: #{msg}\n" }
      logger = logger_class.new(logdev: output, formatter: formatter)

      logger.info("Test message")

      output.rewind
      log_output = output.read
      expect(log_output).to eq("CUSTOM: Test message\n")
    end

    it "respects log levels" do
      output = StringIO.new
      logger = logger_class.new(logdev: output, level: Logger::WARN)

      logger.info("Should not appear")
      logger.warn("Should appear")

      output.rewind
      log_output = output.read

      aggregate_failures do
        expect(log_output).not_to include("Should not appear")
        expect(log_output).to include("Should appear")
      end
    end

    it "supports all standard log levels" do
      logger = logger_class.new

      aggregate_failures do
        expect { logger.debug("debug") }.not_to raise_error
        expect { logger.info("info") }.not_to raise_error
        expect { logger.warn("warn") }.not_to raise_error
        expect { logger.error("error") }.not_to raise_error
        expect { logger.fatal("fatal") }.not_to raise_error
      end
    end
  end

  describe "level setting" do
    it "accepts Logger constant level names" do
      debug_logger = logger_class.new(level: Logger::DEBUG)
      warn_logger = logger_class.new(level: Logger::WARN)
      fatal_logger = logger_class.new(level: Logger::FATAL)

      aggregate_failures do
        expect(debug_logger.level).to eq(Logger::DEBUG)
        expect(warn_logger.level).to eq(Logger::WARN)
        expect(fatal_logger.level).to eq(Logger::FATAL)
      end
    end

    it "accepts integer level values" do
      logger = logger_class.new(level: 3)

      expect(logger.level).to eq(3)
    end
  end
end
