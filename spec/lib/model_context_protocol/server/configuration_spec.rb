require "spec_helper"

RSpec.describe ModelContextProtocol::Server::Configuration do
  subject(:configuration) { described_class.new }

  let(:registry) { ModelContextProtocol::Server::Registry.new }

  describe "#logging_enabled?" do
    context "when enable_log is true" do
      before { configuration.enable_log = true }

      it "returns true" do
        expect(configuration.logging_enabled?).to be true
      end
    end

    context "when enable_log is false" do
      before { configuration.enable_log = false }

      it "returns false" do
        expect(configuration.logging_enabled?).to be false
      end
    end

    context "when enable_log is nil" do
      before { configuration.enable_log = nil }

      it "returns false" do
        expect(configuration.logging_enabled?).to be false
      end
    end
  end

  describe "#validate!" do
    context "with valid configuration" do
      before do
        configuration.name = "test-server"
        configuration.registry = registry
        configuration.version = "1.0.0"
      end

      it "does not raise an error" do
        expect { configuration.validate! }.not_to raise_error
      end
    end

    context "with invalid name" do
      before do
        configuration.name = nil
        configuration.registry = registry
        configuration.version = "1.0.0"
      end

      it "raises InvalidServerNameError" do
        expect { configuration.validate! }.to raise_error(described_class::InvalidServerNameError)
      end
    end

    context "with non-string name" do
      before do
        configuration.name = 123
        configuration.registry = registry
        configuration.version = "1.0.0"
      end

      it "raises InvalidServerNameError" do
        expect { configuration.validate! }.to raise_error(described_class::InvalidServerNameError)
      end
    end

    context "with invalid registry" do
      before do
        configuration.name = "test-server"
        configuration.registry = nil
        configuration.version = "1.0.0"
      end

      it "raises InvalidRegistryError" do
        expect { configuration.validate! }.to raise_error(described_class::InvalidRegistryError)
      end
    end

    context "with non-registry object" do
      before do
        configuration.name = "test-server"
        configuration.registry = "not-a-registry"
        configuration.version = "1.0.0"
      end

      it "raises InvalidRegistryError" do
        expect { configuration.validate! }.to raise_error(described_class::InvalidRegistryError)
      end
    end

    context "with invalid version" do
      before do
        configuration.name = "test-server"
        configuration.registry = registry
        configuration.version = nil
      end

      it "raises InvalidServerVersionError" do
        expect { configuration.validate! }.to raise_error(described_class::InvalidServerVersionError)
      end
    end

    context "with non-string version" do
      before do
        configuration.name = "test-server"
        configuration.registry = registry
        configuration.version = 123
      end

      it "raises InvalidServerVersionError" do
        expect { configuration.validate! }.to raise_error(described_class::InvalidServerVersionError)
      end
    end
  end

  describe "environment variables" do
    context "when requiring environment variables" do
      before do
        configuration.name = "test-server"
        configuration.registry = registry
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
          expect { configuration.validate! }.to raise_error(described_class::MissingRequiredEnvironmentVariable)
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
        configuration.registry = registry
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

  describe "block initialization" do
    it "allows configuration via block" do
      server = ModelContextProtocol::Server.new do |config|
        config.name = "test-server"
        config.registry = registry
        config.version = "1.0.0"
        config.enable_log = true
      end

      config = server.configuration
      expect(config.name).to eq("test-server")
      expect(config.registry).to eq(registry)
      expect(config.version).to eq("1.0.0")
      expect(config.enable_log).to be true
    end
  end
end
