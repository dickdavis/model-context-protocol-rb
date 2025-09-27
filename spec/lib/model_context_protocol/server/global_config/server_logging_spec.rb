require "spec_helper"
require "tempfile"

RSpec.describe ModelContextProtocol::Server::GlobalConfig::ServerLogging do
  subject(:config_class) { described_class }

  before do
    config_class.reset!
  end

  after do
    config_class.reset!
  end

  describe ".configure" do
    it "stores the configuration parameters" do
      aggregate_failures do
        expect {
          config_class.configure do |config|
            config.level = "debug"
            config.progname = "TestServer"
          end
        }.not_to raise_error
        expect(config_class.configured?).to be true
      end
    end

    it "raises error when no block is provided" do
      expect { config_class.configure }.to raise_error(ArgumentError, "Configuration block required")
    end
  end

  describe ".configured?" do
    it "returns false when not configured" do
      expect(config_class.configured?).to be false
    end

    it "returns true when configured" do
      config_class.configure { |config| config.level = Logger::INFO }
      expect(config_class.configured?).to be true
    end
  end

  describe ".logger_params" do
    context "when not configured" do
      it "raises NotConfiguredError" do
        expect { config_class.logger_params }.to raise_error(
          config_class::NotConfiguredError,
          /Server logging not configured/
        )
      end
    end

    context "when configured" do
      it "returns basic configuration parameters" do
        config_class.configure do |config|
          config.level = Logger::DEBUG
          config.progname = "TestServer"
        end

        params = config_class.logger_params
        expect(params).to eq({
          level: Logger::DEBUG,
          progname: "TestServer"
        })
      end

      it "returns parameters with custom output" do
        tempfile = Tempfile.new("test_global_log")

        config_class.configure do |config|
          config.level = Logger::ERROR
          config.logdev = tempfile
          config.progname = "GlobalTest"
        end

        params = config_class.logger_params
        expect(params).to eq({
          level: Logger::ERROR,
          logdev: tempfile,
          progname: "GlobalTest"
        })

        tempfile.close
        tempfile.unlink
      end

      it "returns parameters with custom formatter" do
        custom_formatter = proc { |severity, datetime, progname, msg| "CUSTOM: #{msg}\n" }

        config_class.configure do |config|
          config.level = Logger::INFO
          config.formatter = custom_formatter
          config.progname = "FormatterTest"
        end

        params = config_class.logger_params
        expect(params).to eq({
          level: Logger::INFO,
          formatter: custom_formatter,
          progname: "FormatterTest"
        })
      end

      it "returns parameters with all options configured" do
        tempfile = Tempfile.new("test_all_options")
        custom_formatter = proc { |severity, datetime, progname, msg| "ALL: #{severity} #{msg}\n" }

        config_class.configure do |config|
          config.level = Logger::WARN
          config.logdev = tempfile
          config.formatter = custom_formatter
          config.progname = "AllOptionsTest"
        end

        params = config_class.logger_params
        expect(params).to eq({
          level: Logger::WARN,
          logdev: tempfile,
          formatter: custom_formatter,
          progname: "AllOptionsTest"
        })

        tempfile.close
        tempfile.unlink
      end

      it "includes default values in parameters" do
        config_class.configure do |config|
          config.level = Logger::WARN
        end

        params = config_class.logger_params
        expect(params).to eq({
          level: Logger::WARN,
          progname: "MCP-Server"
        })
      end

      describe "individual configuration options" do
        it "configures level only" do
          config_class.configure do |config|
            config.level = Logger::FATAL
          end

          params = config_class.logger_params
          aggregate_failures do
            expect(params[:level]).to eq(Logger::FATAL)
            expect(params[:progname]).to eq("MCP-Server")
            expect(params[:logdev]).to be_nil
            expect(params[:formatter]).to be_nil
          end
        end

        it "configures logdev only" do
          tempfile = Tempfile.new("logdev_only")

          config_class.configure do |config|
            config.logdev = tempfile
          end

          params = config_class.logger_params
          aggregate_failures do
            expect(params[:logdev]).to eq(tempfile)
            expect(params[:level]).to eq(Logger::INFO)
            expect(params[:progname]).to eq("MCP-Server")
            expect(params[:formatter]).to be_nil
          end

          tempfile.close
          tempfile.unlink
        end

        it "configures formatter only" do
          custom_formatter = proc { |severity, datetime, progname, msg| "ONLY: #{msg}\n" }

          config_class.configure do |config|
            config.formatter = custom_formatter
          end

          params = config_class.logger_params
          aggregate_failures do
            expect(params[:formatter]).to eq(custom_formatter)
            expect(params[:level]).to eq(Logger::INFO)
            expect(params[:progname]).to eq("MCP-Server")
            expect(params[:logdev]).to be_nil
          end
        end

        it "configures progname only" do
          config_class.configure do |config|
            config.progname = "OnlyProgname"
          end

          params = config_class.logger_params
          aggregate_failures do
            expect(params[:progname]).to eq("OnlyProgname")
            expect(params[:level]).to eq(Logger::INFO)
            expect(params[:logdev]).to be_nil
            expect(params[:formatter]).to be_nil
          end
        end
      end
    end
  end

  describe ".reset!" do
    it "resets all configuration state" do
      config_class.configure { |config| config.level = Logger::DEBUG }
      expect(config_class.configured?).to be true

      config_class.reset!

      expect(config_class.configured?).to be false
      expect { config_class.logger_params }.to raise_error(config_class::NotConfiguredError)
    end
  end
end
