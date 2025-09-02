require "spec_helper"

RSpec.describe ModelContextProtocol::Server::Configuration do
  subject(:configuration) { described_class.new }

  let(:registry) { ModelContextProtocol::Server::Registry.new }

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

    context "when invalid transport provided" do
      before do
        configuration.name = "test-server"
        configuration.registry = registry
        configuration.version = "1.0.0"
        configuration.transport = {type: :unknown_transport}
      end

      it "raises InvalidTransportError" do
        expect { configuration.validate! }.to raise_error(
          described_class::InvalidTransportError,
          "Unknown transport type: unknown_transport"
        )
      end
    end

    context "when stdio transport provided" do
      before do
        configuration.name = "test-server"
        configuration.registry = registry
        configuration.version = "1.0.0"
      end

      it "validates successfully with symbol" do
        configuration.transport = :stdio
        expect { configuration.validate! }.not_to raise_error
      end

      it "validates successfully with hash format" do
        configuration.transport = {type: :stdio}
        expect { configuration.validate! }.not_to raise_error
      end
    end

    context "when streamable_http transport provided" do
      before do
        configuration.name = "test-server"
        configuration.registry = registry
        configuration.version = "1.0.0"
      end

      context "with invalid transport options specified" do
        it "raises error when redis_client is missing" do
          configuration.transport = {type: :streamable_http}

          expect { configuration.validate! }.to raise_error(
            described_class::InvalidTransportError,
            "streamable_http transport requires redis_client option"
          )
        end

        it "raises error when redis_client is not Redis-compatible" do
          configuration.transport = {
            type: :streamable_http,
            redis_client: "not a redis client"
          }

          expect { configuration.validate! }.to raise_error(
            described_class::InvalidTransportError,
            "redis_client must be a Redis-compatible client"
          )
        end
      end

      context "with valid transport options specified" do
        it "validates successfully" do
          configuration.transport = {
            type: :streamable_http,
            redis_client: MockRedis.new
          }

          expect { configuration.validate! }.not_to raise_error
        end
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

  describe "#context" do
    context "when not previously set" do
      it "returns an empty hash" do
        expect(configuration.context).to eq({})
      end

      it "memoizes the empty hash" do
        first_call = configuration.context
        second_call = configuration.context
        expect(first_call).to be(second_call)
      end
    end

    context "when previously set" do
      before { configuration.context = {key: "value"} }

      it "returns the set hash" do
        expect(configuration.context).to eq({key: "value"})
      end
    end
  end

  describe "#context=" do
    it "sets the context hash" do
      test_context = {foo: "bar", baz: 42}
      configuration.context = test_context
      expect(configuration.context).to eq(test_context)
    end

    it "overrides memoized value" do
      configuration.context
      new_context = {new: "value"}
      configuration.context = new_context
      expect(configuration.context).to eq(new_context)
    end

    it "accepts an empty hash" do
      configuration.context = {}
      expect(configuration.context).to eq({})
    end

    it "accepts nil and converts to empty hash when accessed" do
      configuration.context = nil
      expect(configuration.context).to eq({})
    end
  end

  describe "#transport_type" do
    context "when transport is a hash" do
      it "returns the type from symbol key" do
        configuration.transport = {type: :streamable_http}
        expect(configuration.transport_type).to eq(:streamable_http)
      end

      it "returns the type from string key" do
        configuration.transport = {"type" => :streamable_http}
        expect(configuration.transport_type).to eq(:streamable_http)
      end
    end

    context "when transport is a symbol" do
      it "returns the symbol" do
        configuration.transport = :stdio
        expect(configuration.transport_type).to eq(:stdio)
      end
    end

    context "when transport is a string" do
      it "returns the symbol" do
        configuration.transport = "stdio"
        expect(configuration.transport_type).to eq(:stdio)
      end
    end

    context "when transport is nil" do
      it "returns nil" do
        configuration.transport = nil
        expect(configuration.transport_type).to be_nil
      end
    end
  end

  describe "#transport_options" do
    context "when transport is a hash" do
      it "returns options excluding type" do
        configuration.transport = {
          type: :streamable_http,
          redis_client: "mock_redis",
          session_ttl: 1800,
          string_key: "value"
        }

        expect(configuration.transport_options).to eq({
          redis_client: "mock_redis",
          session_ttl: 1800,
          string_key: "value"
        })
      end
    end

    context "when transport is not a hash" do
      it "returns empty hash for symbol transport" do
        configuration.transport = :stdio
        expect(configuration.transport_options).to eq({})
      end

      it "returns empty hash for nil transport" do
        configuration.transport = nil
        expect(configuration.transport_options).to eq({})
      end
    end
  end
end
