module ModelContextProtocol
  # Settings for servers that communicate via stdin/stdout, typically used by
  # standalone scripts launched by clients like Claude Desktop.
  #
  # Created by Server.with_stdio_transport, which yields an instance to a configuration
  # block before passing it to Router. Adds environment variable management (via
  # set_environment_variable and require_environment_variable) on top of the base class,
  # and enforces that server_logger cannot write to stdout (which would corrupt the protocol).
  #
  # Router queries apply_environment_variables? (true for this subclass) and calls
  # execute_with_context to temporarily modify ENV before executing handlers. This is
  # safe because stdio servers are single-threaded; see StreamableHttpConfiguration
  # for the multi-threaded alternative.
  class Server::StdioConfiguration < Server::Configuration
    # @return [Symbol] :stdio (used by Server.start to instantiate StdioTransport)
    def transport_type = :stdio

    # @return [Boolean] true (Router modifies ENV before executing handlers because
    #   stdin/stdout servers run single-threaded and ENV mutation is safe)
    def apply_environment_variables? = true

    # Access the hash of programmatically-set variables.
    # Router merges these with ENV via execute_with_context before executing handlers,
    # making them available to prompts, resources, and tools through ENV lookups.
    # Variables set here take precedence over shell environment variables.
    #
    # @return [Hash<String, String>] lazily-initialized hash mapping uppercase keys to values
    def environment_variables
      @environment_variables ||= {}
    end

    # Retrieve a variable's value by key, checking the programmatic store first then ENV.
    # Used by validate_environment_variables! to verify that required variables are set.
    # Keys are normalized to uppercase for consistent lookups.
    #
    # @param key [String, Symbol] the variable name (case-insensitive; normalized to uppercase)
    # @return [String, nil] the value from environment_variables or ENV, or nil if unset
    def environment_variable(key)
      environment_variables[key.to_s.upcase] || ENV[key.to_s.upcase]
    end

    # Store a variable that Router will merge into ENV before executing handlers.
    # Useful for secrets retrieved from password managers or encrypted vaults instead of
    # relying on shell ENV. Called "environment variables" to match MCP specification
    # terminology even though they're configuration values.
    #
    # See https://modelcontextprotocol.io/docs/tools/debugging#environment-variables
    #
    # @param key [String, Symbol] the variable name (normalized to uppercase)
    # @param value [String] the value to store (overwrites ENV[key] during handler execution)
    # @return [String] the stored value
    def set_environment_variable(key, value)
      environment_variables[key.to_s.upcase] = value
    end

    # Declare a variable that must be present at validation time.
    # Adds the key to an internal tracking list; validate_environment_variables! raises
    # MissingRequiredEnvironmentVariable if environment_variable(key) returns nil.
    # Use this for API keys or database URLs needed by handlers.
    #
    # @param key [String, Symbol] the variable name (normalized to uppercase)
    # @return [Array<String>] the updated list of required variables (for chaining)
    def require_environment_variable(key)
      required_environment_variables << key.to_s.upcase
    end

    private

    # Internal storage for variables declared via require_environment_variable.
    # Checked by validate_environment_variables! during validate! call.
    #
    # @return [Array<String>] list of uppercase keys that must be present
    def required_environment_variables
      @required_environment_variables ||= []
    end

    # Verify stdio-specific constraints: required variables are set and logger doesn't write to stdout.
    # Overrides the base class template method; called by validate! after checking name/version/registry.
    #
    # @raise [MissingRequiredEnvironmentVariable] if any required variable is unset
    # @raise [ServerLogger::StdoutNotAllowedError] if server_logger.logdev is $stdout
    # @return [void]
    def validate_transport!
      validate_environment_variables!
      validate_server_logging_transport_constraints!
    end

    # Check that all variables declared via require_environment_variable are present.
    # Called by validate_transport! to fail fast before starting the server if
    # configuration is incomplete.
    #
    # @raise [MissingRequiredEnvironmentVariable] if environment_variable(key) returns nil for any required key
    # @return [void]
    def validate_environment_variables!
      required_environment_variables.each do |key|
        raise MissingRequiredEnvironmentVariable, "#{key} is not set" unless environment_variable(key)
      end
    end

    # Verify that server_logger isn't writing to stdout, which would interleave
    # diagnostic output with JSON-RPC protocol messages on stdout, corrupting the stream
    # that clients parse. StdioTransport reads from stdin and writes to stdout exclusively
    # for protocol messages.
    #
    # @raise [ServerLogger::StdoutNotAllowedError] if server_logger.logdev is $stdout
    # @return [void]
    def validate_server_logging_transport_constraints!
      return unless server_logger.logdev == $stdout

      raise ModelContextProtocol::Server::ServerLogger::StdoutNotAllowedError,
        "StdioTransport cannot log to stdout. Use stderr or a file instead."
    end
  end
end
