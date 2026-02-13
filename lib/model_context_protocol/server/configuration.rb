module ModelContextProtocol
  # Base settings container for MCP servers with two concrete subclasses:
  # - {StdioConfiguration} for standalone scripts using stdin/stdout
  # - {StreamableHttpConfiguration} for Rack applications using streamable HTTP with Redis
  #
  # Server.rb factory methods (with_stdio_transport, with_streamable_http_transport)
  # instantiate the appropriate subclass, yield it to a block for population, validate
  # it, then pass it to Router.new. Router reads pagination settings via pagination_options
  # and queries transport capabilities via supports_list_changed? and apply_environment_variables?.
  #
  # The base class provides shared attributes (name, version, registry, pagination) and
  # validation logic, while subclasses override transport_type and validate_transport! to
  # enforce transport-specific constraints.
  class Server::Configuration
    # Signals that the server's identifying name is missing or not a String.
    # Raised by validate! when name is nil or non-String.
    class InvalidServerNameError < StandardError; end

    # Signals that the server's version string is missing or not a String.
    # Raised by validate! when version is nil or non-String.
    class InvalidServerVersionError < StandardError; end

    # Signals that the optional UI title is non-nil but not a String.
    # Raised by validate_title! when title is set to a non-String value.
    class InvalidServerTitleError < StandardError; end

    # Signals that the optional LLM instructions are non-nil but not a String.
    # Raised by validate_instructions! when instructions is set to a non-String value.
    class InvalidServerInstructionsError < StandardError; end

    # Signals that the registry is missing or not a Registry instance.
    # Raised by validate! when registry is nil or not a ModelContextProtocol::Server::Registry.
    class InvalidRegistryError < StandardError; end

    # Signals that a required environment variable is absent (stdio transport only).
    # Raised by StdioConfiguration#validate_environment_variables! when a variable
    # declared via require_environment_variable is not set.
    class MissingRequiredEnvironmentVariable < StandardError; end

    # Signals transport-specific validation failure (Redis missing for HTTP, stdout conflict for stdio).
    # Raised by subclass implementations of validate_transport! when prerequisites are unmet.
    class InvalidTransportError < StandardError; end

    # Signals that pagination settings are invalid (negative sizes, out-of-range defaults).
    # Raised by validate_pagination! when default_page_size exceeds max_page_size or values are non-positive.
    class InvalidPaginationError < StandardError; end

    # @!attribute [rw] name
    #   @return [String] the server's identifying name (sent in initialize response serverInfo.name)
    attr_accessor :name

    # @!attribute [rw] version
    #   @return [String] the server's version string (sent in initialize response serverInfo.version)
    attr_accessor :version

    # @!attribute [rw] pagination
    #   @return [Hash, false, nil] pagination settings or false to disable;
    #     Router calls pagination_options to extract default_page_size, max_page_size, and cursor_ttl
    #     when handling list requests (resources/list, prompts/list, tools/list).
    #     Accepts Hash with :enabled, :default_page_size, :max_page_size, :cursor_ttl keys, or false to disable.
    attr_accessor :pagination

    # @!attribute [rw] title
    #   @return [String, nil] optional human-readable display title for Claude Desktop UI
    #     (sent in initialize response serverInfo.title if present)
    attr_accessor :title

    # @!attribute [rw] instructions
    #   @return [String, nil] optional guidance for LLMs on how to use the server
    #     (sent in initialize response instructions field if present)
    attr_accessor :instructions

    # @!attribute [r] client_logger
    #   @return [ClientLogger] logger for sending notifications/message to MCP clients via JSON-RPC;
    #     Router passes this to prompts, resources, and tools so they can log to the client
    attr_reader :client_logger

    # Lazily-built Ruby Logger for server-side diagnostics (not sent to clients).
    # Reads from GlobalConfig::ServerLogging on first access so that
    # Server.configure_server_logging can be called before or after the factory method.
    #
    # @return [ServerLogger] writes to stderr by default, or configured destination via configure_server_logging
    def server_logger
      @server_logger ||= begin
        params = if ModelContextProtocol::Server::GlobalConfig::ServerLogging.configured?
          ModelContextProtocol::Server::GlobalConfig::ServerLogging.logger_params
        else
          {}
        end
        ModelContextProtocol::Server::ServerLogger.new(**params)
      end
    end

    # Initialize shared attributes and loggers for any configuration subclass.
    # ClientLogger queues messages until a transport connects; ServerLogger is built
    # lazily on first access via #server_logger.
    def initialize
      @client_logger = ModelContextProtocol::Server::ClientLogger.new(
        logger_name: "server",
        level: "info"
      )
    end

    # Create and store a Registry from a block defining prompts, resources, and tools.
    # Router queries the resulting registry to handle resources/list, tools/call, etc.
    #
    # @yieldparam (see Registry.new)
    # @return [ModelContextProtocol::Server::Registry] the created registry
    # @example
    #   config.registry do
    #     tools { register MyTool }
    #   end
    def registry(&block)
      return @registry unless block

      @registry = ModelContextProtocol::Server::Registry.new(&block)
    end

    # Identify the transport layer for this configuration.
    # Subclasses return :stdio or :streamable_http; Server.start uses this to
    # instantiate the correct Transport class (StdioTransport or StreamableHttpTransport).
    #
    # @return [Symbol, nil] nil in the base class (never instantiated directly)
    def transport_type = nil

    # Determine whether the transport supports notifications/resources/list_changed
    # and notifications/tools/list_changed. Router queries this when building the
    # initialize response capabilities hash (adding listChanged: true to prompts/resources/tools).
    # Only HTTP transport returns true (stdio can't push unsolicited notifications).
    #
    # @return [Boolean] false in base class and StdioConfiguration, true in StreamableHttpConfiguration
    def supports_list_changed? = false

    # Determine whether Router should modify ENV before executing handlers.
    # StdioConfiguration returns true because stdin/stdout scripts run single-threaded
    # and ENV mutation is safe. StreamableHttpConfiguration returns false because
    # ENV is global and modifying it in a multi-threaded Rack server creates race conditions.
    #
    # @return [Boolean] false in base class, overridden by subclasses
    def apply_environment_variables? = false

    # Check whether pagination is active for list responses (resources/list, prompts/list, tools/list).
    # Router calls this before extracting pagination params; if false, it returns unpaginated results.
    # Enabled by default (nil or true), or when pagination Hash has enabled != false.
    #
    # @return [Boolean] true unless pagination is explicitly set to false
    def pagination_enabled?
      return true if pagination.nil?

      case pagination
      when Hash
        pagination[:enabled] != false
      when false
        false
      else
        true
      end
    end

    # Extract normalized pagination settings for Router to pass to Pagination.extract_pagination_params.
    # Router uses default_page_size and max_page_size to validate cursor and page size params from the client,
    # and cursor_ttl to configure how long the Pagination module stores cursor state in memory.
    #
    # @return [Hash] pagination parameters with keys :enabled, :default_page_size, :max_page_size, :cursor_ttl;
    #   defaults are 100, 1000, and 3600 (1 hour) respectively
    def pagination_options
      case pagination
      when Hash
        {
          enabled: pagination[:enabled] != false,
          default_page_size: pagination[:default_page_size] || 100,
          max_page_size: pagination[:max_page_size] || 1000,
          cursor_ttl: pagination[:cursor_ttl] || 3600
        }
      when false
        {enabled: false}
      else
        {
          enabled: true,
          default_page_size: 100,
          max_page_size: 1000,
          cursor_ttl: 3600
        }
      end
    end

    # Verify all required attributes and transport-specific constraints.
    # Called by Server.build_server (the factory method's internal logic) after yielding
    # the configuration block but before constructing the Router. Ensures the configuration
    # is complete and internally consistent.
    #
    # @raise [InvalidServerNameError] if name is nil or non-String
    # @raise [InvalidRegistryError] if registry is nil or not a Registry instance
    # @raise [InvalidServerVersionError] if version is nil or non-String
    # @raise [InvalidTransportError] if transport prerequisites fail (subclass-specific)
    # @raise [InvalidPaginationError] if page sizes are negative or out of range
    # @raise [InvalidServerTitleError] if title is non-nil but not a String
    # @raise [InvalidServerInstructionsError] if instructions is non-nil but not a String
    # @return [void]
    def validate!
      raise InvalidServerNameError unless valid_name?
      raise InvalidRegistryError unless valid_registry?
      raise InvalidServerVersionError unless valid_version?

      validate_transport!
      validate_pagination!
      validate_title!
      validate_instructions!
    end

    # Access server-wide key-value storage merged with per-request session_context by Router.
    # Router.effective_context merges this with Thread.current[:mcp_context][:session_context],
    # then passes the result to prompts, resources, and tools so they can access both
    # server-level (shared across all requests) and session-level (specific to HTTP session) data.
    #
    # @return [Hash] the lazily-initialized context hash (defaults to {})
    def context
      @context ||= {}
    end

    # Replace the server-wide context with a new hash.
    # Router reads this via effective_context, merging it with session-level data before
    # passing to handler implementations.
    #
    # @param context_hash [Hash] the new context to store (defaults to {})
    # @return [Hash] the stored context
    def context=(context_hash = {})
      @context = context_hash
    end

    private

    # Template method for subclass-specific transport validation.
    # StdioConfiguration checks that required environment variables are set and that
    # server_logger isn't writing to stdout (which would corrupt the stdio protocol).
    # StreamableHttpConfiguration validates that redis_url is a valid Redis URL.
    #
    # @raise [InvalidTransportError] when transport prerequisites are unmet
    # @raise [MissingRequiredEnvironmentVariable] when stdio transport requires an unset variable
    # @return [void]
    def validate_transport!
      # Template method — subclasses override to add transport-specific validations
    end

    # Template method for subclass-specific transport setup (side effects).
    # Called by Server.build_server after validate! passes. Separated from validate_transport!
    # because validation should be pure (no side effects), while setup performs actions like
    # creating connection pools.
    # StreamableHttpConfiguration overrides this to configure the Redis connection pool.
    #
    # @return [void]
    def setup_transport!
      # Template method — subclasses override to perform transport-specific setup
    end

    # Check that name attribute is a non-nil String.
    # Called by validate! to ensure the initialize response can be constructed.
    #
    # @return [Boolean] true if name is a String
    def valid_name?
      name&.is_a?(String)
    end

    # Check that registry attribute is a Registry instance.
    # Called by validate! to ensure Router can query tools, prompts, and resources.
    #
    # @return [Boolean] true if registry is a ModelContextProtocol::Server::Registry
    def valid_registry?
      registry&.is_a?(ModelContextProtocol::Server::Registry)
    end

    # Check that version attribute is a non-nil String.
    # Called by validate! to ensure the initialize response can be constructed.
    #
    # @return [Boolean] true if version is a String
    def valid_version?
      version&.is_a?(String)
    end

    # Verify pagination settings are internally consistent (page sizes positive, defaults in range).
    # Called by validate! only when pagination_enabled? is true; skipped if pagination is false.
    # Ensures Router won't pass invalid params to Pagination.extract_pagination_params.
    #
    # @raise [InvalidPaginationError] if max_page_size <= 0, default_page_size <= 0,
    #   default_page_size > max_page_size, or cursor_ttl < 0
    # @return [void]
    def validate_pagination!
      return unless pagination_enabled?

      opts = pagination_options

      if opts[:max_page_size] <= 0
        raise InvalidPaginationError, "Invalid pagination max_page_size: must be positive"
      end

      if opts[:default_page_size] <= 0 || opts[:default_page_size] > opts[:max_page_size]
        raise InvalidPaginationError, "Invalid pagination default_page_size: must be between 1 and #{opts[:max_page_size]}"
      end

      if opts[:cursor_ttl] && opts[:cursor_ttl] <= 0
        raise InvalidPaginationError, "Invalid pagination cursor_ttl: must be positive or nil"
      end
    end

    # Check that the optional title attribute is nil or a String.
    # Called by validate! to ensure the initialize response serverInfo.title is valid.
    #
    # @raise [InvalidServerTitleError] if title is non-nil and not a String
    # @return [void]
    def validate_title!
      return if title.nil?
      return if title.is_a?(String)

      raise InvalidServerTitleError, "Server title must be a string"
    end

    # Check that the optional instructions attribute is nil or a String.
    # Called by validate! to ensure the initialize response instructions field is valid.
    #
    # @raise [InvalidServerInstructionsError] if instructions is non-nil and not a String
    # @return [void]
    def validate_instructions!
      return if instructions.nil?
      return if instructions.is_a?(String)

      raise InvalidServerInstructionsError, "Server instructions must be a string"
    end
  end
end
