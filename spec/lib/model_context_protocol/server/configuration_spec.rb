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
      end

      config = server.configuration
      aggregate_failures do
        expect(config.name).to eq("test-server")
        expect(config.registry).to eq(registry)
        expect(config.version).to eq("1.0.0")
      end
    end
  end

  describe "#client_logger" do
    it "always provides a logger instance" do
      expect(configuration.client_logger).to be_a(ModelContextProtocol::Server::ClientLogger)
    end

    it "sets default logger name to 'server'" do
      expect(configuration.client_logger.logger_name).to eq("server")
    end

    it "sets default log level to INFO" do
      expect(configuration.client_logger.level).to eq(Logger::INFO)
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
        it "raises error when Redis is not configured globally" do
          configuration.transport = {type: :streamable_http}

          expect { configuration.validate! }.to raise_error(
            described_class::InvalidTransportError,
            /streamable_http transport requires Redis configuration/
          )
        end
      end

      context "with valid transport options specified" do
        it "validates successfully" do
          ModelContextProtocol::Server::RedisConfig.configure do |config|
            config.redis_url = "redis://localhost:6379/15"
          end

          configuration.transport = {
            type: :streamable_http
          }

          expect { configuration.validate! }.not_to raise_error
        end
      end
    end

    context "with valid pagination settings" do
      before do
        configuration.name = "test-server"
        configuration.registry = registry
        configuration.version = "1.0.0"
      end

      it "validates successfully with defaults" do
        expect { configuration.validate! }.not_to raise_error
      end

      it "validates successfully with custom settings" do
        configuration.pagination = {
          default_page_size: 50,
          max_page_size: 500,
          cursor_ttl: 1800
        }

        expect { configuration.validate! }.not_to raise_error
      end

      it "validates successfully when disabled" do
        configuration.pagination = false

        expect { configuration.validate! }.not_to raise_error
      end
    end

    context "with invalid pagination settings" do
      before do
        configuration.name = "test-server"
        configuration.registry = registry
        configuration.version = "1.0.0"
      end

      it "raises error when default_page_size is zero" do
        configuration.pagination = {default_page_size: 0}

        expect { configuration.validate! }.to raise_error(
          described_class::InvalidPaginationError,
          /Invalid pagination default_page_size: must be between 1 and 1000/
        )
      end

      it "raises error when default_page_size is negative" do
        configuration.pagination = {default_page_size: -10}

        expect { configuration.validate! }.to raise_error(
          described_class::InvalidPaginationError,
          /Invalid pagination default_page_size: must be between 1 and 1000/
        )
      end

      it "raises error when default_page_size exceeds max_page_size" do
        configuration.pagination = {
          default_page_size: 1000,
          max_page_size: 100
        }

        expect { configuration.validate! }.to raise_error(
          described_class::InvalidPaginationError,
          /Invalid pagination default_page_size: must be between 1 and 100/
        )
      end

      it "raises error when max_page_size is zero" do
        configuration.pagination = {max_page_size: 0}

        expect { configuration.validate! }.to raise_error(
          described_class::InvalidPaginationError,
          /Invalid pagination max_page_size: must be positive/
        )
      end

      it "raises error when max_page_size is negative" do
        configuration.pagination = {max_page_size: -5}

        expect { configuration.validate! }.to raise_error(
          described_class::InvalidPaginationError,
          /Invalid pagination max_page_size: must be positive/
        )
      end

      it "raises error when cursor_ttl is zero" do
        configuration.pagination = {cursor_ttl: 0}

        expect { configuration.validate! }.to raise_error(
          described_class::InvalidPaginationError,
          /Invalid pagination cursor_ttl: must be positive or nil/
        )
      end

      it "raises error when cursor_ttl is negative" do
        configuration.pagination = {cursor_ttl: -100}

        expect { configuration.validate! }.to raise_error(
          described_class::InvalidPaginationError,
          /Invalid pagination cursor_ttl: must be positive or nil/
        )
      end

      it "allows cursor_ttl to be nil" do
        configuration.pagination = {cursor_ttl: nil}

        expect { configuration.validate! }.not_to raise_error
      end
    end

    context "with title" do
      before do
        configuration.name = "test-server"
        configuration.registry = registry
        configuration.version = "1.0.0"
      end

      it "validates successfully when title is a string" do
        configuration.title = "My Test Server"

        expect { configuration.validate! }.not_to raise_error
      end

      it "validates successfully when title is nil" do
        configuration.title = nil

        expect { configuration.validate! }.not_to raise_error
      end

      it "raises error when title is not a string" do
        configuration.title = 123

        expect { configuration.validate! }.to raise_error(
          described_class::InvalidServerTitleError,
          "Server title must be a string"
        )
      end

      it "raises error when title is an array" do
        configuration.title = ["not", "a", "string"]

        expect { configuration.validate! }.to raise_error(
          described_class::InvalidServerTitleError,
          "Server title must be a string"
        )
      end

      it "raises error when title is a hash" do
        configuration.title = {name: "test"}

        expect { configuration.validate! }.to raise_error(
          described_class::InvalidServerTitleError,
          "Server title must be a string"
        )
      end
    end

    context "with instructions" do
      before do
        configuration.name = "test-server"
        configuration.registry = registry
        configuration.version = "1.0.0"
      end

      it "validates successfully when instructions is a string" do
        configuration.instructions = "Use this server for testing."

        expect { configuration.validate! }.not_to raise_error
      end

      it "validates successfully when instructions is nil" do
        configuration.instructions = nil

        expect { configuration.validate! }.not_to raise_error
      end

      it "validates successfully when instructions is a multi-line string" do
        configuration.instructions = <<~INSTRUCTIONS
          This server provides test capabilities.
          
          Key features:
          - Feature one
          - Feature two
        INSTRUCTIONS

        expect { configuration.validate! }.not_to raise_error
      end

      it "raises error when instructions is not a string" do
        configuration.instructions = []

        expect { configuration.validate! }.to raise_error(
          described_class::InvalidServerInstructionsError,
          "Server instructions must be a string"
        )
      end

      it "raises error when instructions is a number" do
        configuration.instructions = 456

        expect { configuration.validate! }.to raise_error(
          described_class::InvalidServerInstructionsError,
          "Server instructions must be a string"
        )
      end

      it "raises error when instructions is a hash" do
        configuration.instructions = {message: "test instructions"}

        expect { configuration.validate! }.to raise_error(
          described_class::InvalidServerInstructionsError,
          "Server instructions must be a string"
        )
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
          session_ttl: 1800,
          string_key: "value"
        }

        expect(configuration.transport_options).to eq({
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

  describe "#pagination_enabled?" do
    it "returns true by default" do
      expect(configuration.pagination_enabled?).to be true
    end

    it "returns true when pagination is nil" do
      configuration.pagination = nil
      expect(configuration.pagination_enabled?).to be true
    end

    it "returns true when pagination is empty hash" do
      configuration.pagination = {}
      expect(configuration.pagination_enabled?).to be true
    end

    it "returns true when pagination hash has enabled: true" do
      configuration.pagination = {enabled: true}
      expect(configuration.pagination_enabled?).to be true
    end

    it "returns false when pagination hash has enabled: false" do
      configuration.pagination = {enabled: false}
      expect(configuration.pagination_enabled?).to be false
    end

    it "returns false when pagination is false" do
      configuration.pagination = false
      expect(configuration.pagination_enabled?).to be false
    end

    it "returns true for any other value" do
      configuration.pagination = "anything"
      expect(configuration.pagination_enabled?).to be true
    end
  end

  describe "#pagination_options" do
    context "when pagination is not set" do
      it "returns default options" do
        expect(configuration.pagination_options).to eq({
          enabled: true,
          default_page_size: 100,
          max_page_size: 1000,
          cursor_ttl: 3600
        })
      end
    end

    context "when pagination is false" do
      it "returns disabled options" do
        configuration.pagination = false
        expect(configuration.pagination_options).to eq({enabled: false})
      end
    end

    context "when pagination is a hash" do
      it "merges with defaults" do
        configuration.pagination = {
          default_page_size: 50,
          max_page_size: 500
        }

        expect(configuration.pagination_options).to eq({
          enabled: true,
          default_page_size: 50,
          max_page_size: 500,
          cursor_ttl: 3600
        })
      end

      it "respects explicit enabled: false" do
        configuration.pagination = {
          enabled: false,
          default_page_size: 25
        }

        expect(configuration.pagination_options).to eq({
          enabled: false,
          default_page_size: 25,
          max_page_size: 1000,
          cursor_ttl: 3600
        })
      end

      it "handles all custom options" do
        configuration.pagination = {
          enabled: true,
          default_page_size: 20,
          max_page_size: 200,
          cursor_ttl: 1800
        }

        expect(configuration.pagination_options).to eq({
          enabled: true,
          default_page_size: 20,
          max_page_size: 200,
          cursor_ttl: 1800
        })
      end
    end
  end
end
