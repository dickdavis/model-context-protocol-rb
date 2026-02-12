require "spec_helper"

RSpec.describe ModelContextProtocol::Server::StdioConfiguration do
  subject(:configuration) { described_class.new }

  describe "block initialization" do
    before(:each) do
      ModelContextProtocol::Server.reset!
    end

    after(:each) do
      ModelContextProtocol::Server.reset!
    end

    it "allows configuration via factory method" do
      server = ModelContextProtocol::Server.with_stdio_transport do |config|
        config.name = "test-server"
        config.registry {}
        config.version = "1.0.0"
      end

      config = server.configuration
      aggregate_failures do
        expect(config).to be_a(described_class)
        expect(config.name).to eq("test-server")
        expect(config.registry).to be_a(ModelContextProtocol::Server::Registry)
        expect(config.version).to eq("1.0.0")
      end
    end
  end

  describe "transport type" do
    it "returns :stdio" do
      expect(configuration.transport_type).to eq(:stdio)
    end

    it "returns true for apply_environment_variables?" do
      expect(configuration.apply_environment_variables?).to be true
    end

    it "returns false for supports_list_changed?" do
      expect(configuration.supports_list_changed?).to be false
    end
  end

  describe "environment variables" do
    context "when requiring environment variables" do
      before do
        configuration.name = "test-server"
        configuration.registry {}
        configuration.version = "1.0.0"
        configuration.require_environment_variable("TEST_VAR")
      end

      context "when the environment variable is set" do
        before { ENV["TEST_VAR"] = "test-value" }

        it "does not raise an error" do
          expect { configuration.validate! }.not_to raise_error
        end

        it "returns the environment variable value" do
          expect(configuration.environment_variable("TEST_VAR")).to eq("test-value")
        end
      end

      context "when the environment variable is not set" do
        before { ENV.delete("TEST_VAR") }

        it "raises MissingRequiredEnvironmentVariable" do
          expect { configuration.validate! }.to raise_error(
            ModelContextProtocol::Server::Configuration::MissingRequiredEnvironmentVariable
          )
        end

        it "returns nil" do
          expect(configuration.environment_variable("TEST_VAR")).to be_nil
        end
      end

      context "when setting environment variable programmatically" do
        before do
          configuration.set_environment_variable("TEST_VAR", "programmatic-value")
          ENV.delete("TEST_VAR")
        end

        it "does not raise an error" do
          expect { configuration.validate! }.not_to raise_error
        end

        it "returns the programmatically set value" do
          expect(configuration.environment_variable("TEST_VAR")).to eq("programmatic-value")
        end
      end
    end

    context "when not requiring environment variables" do
      before do
        configuration.name = "test-server"
        configuration.registry {}
        configuration.version = "1.0.0"
      end

      it "does not raise an error when environment variable is not set" do
        ENV.delete("TEST_VAR")
        expect { configuration.validate! }.not_to raise_error
      end

      it "returns nil for unset environment variable" do
        expect(configuration.environment_variable("TEST_VAR")).to be_nil
      end
    end
  end

  describe "server logging transport constraints" do
    after do
      ModelContextProtocol::Server::GlobalConfig::ServerLogging.reset!
    end

    it "raises error when stdio transport with stdout logger" do
      ModelContextProtocol::Server.configure_server_logging do |config|
        config.logdev = $stdout
      end

      config = described_class.new
      config.name = "test-server"
      config.version = "1.0.0"
      config.registry {}

      expect { config.validate! }.to raise_error(/StdioTransport cannot log to stdout/)
    end
  end
end
