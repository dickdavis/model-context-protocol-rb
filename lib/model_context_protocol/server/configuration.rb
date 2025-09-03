require_relative "mcp_logger"

module ModelContextProtocol
  class Server::Configuration
    # Raised when configured with invalid name.
    class InvalidServerNameError < StandardError; end

    # Raised when configured with invalid version.
    class InvalidServerVersionError < StandardError; end

    # Raised when configured with invalid title.
    class InvalidServerTitleError < StandardError; end

    # Raised when configured with invalid instructions.
    class InvalidServerInstructionsError < StandardError; end

    # Raised when configured with invalid registry.
    class InvalidRegistryError < StandardError; end

    # Raised when a required environment variable is not set
    class MissingRequiredEnvironmentVariable < StandardError; end

    # Raised when transport configuration is invalid
    class InvalidTransportError < StandardError; end

    # Raised when an invalid log level is provided
    class InvalidLogLevelError < StandardError; end

    # Raised when pagination configuration is invalid
    class InvalidPaginationError < StandardError; end

    # Valid MCP log levels per the specification
    VALID_LOG_LEVELS = %w[debug info notice warning error critical alert emergency].freeze

    attr_accessor :name, :registry, :version, :transport, :pagination, :title, :instructions
    attr_reader :logger

    def initialize
      @logging_enabled = true
      @default_log_level = "info"
      @logger = ModelContextProtocol::Server::MCPLogger.new(
        logger_name: "server",
        level: @default_log_level,
        enabled: @logging_enabled
      )
    end

    def logging_enabled?
      @logging_enabled
    end

    def logging_enabled=(value)
      @logging_enabled = value
      @logger = ModelContextProtocol::Server::MCPLogger.new(
        logger_name: "server",
        level: @default_log_level,
        enabled: value
      )
    end

    def default_log_level=(level)
      unless VALID_LOG_LEVELS.include?(level.to_s)
        raise InvalidLogLevelError, "Invalid log level: #{level}. Valid levels are: #{VALID_LOG_LEVELS.join(", ")}"
      end

      @default_log_level = level.to_s
      @logger.set_mcp_level(@default_log_level)
    end

    def transport_type
      case transport
      when Hash
        transport[:type] || transport["type"]
      when Symbol, String
        transport.to_sym
      end
    end

    def transport_options
      case transport
      when Hash
        transport.except(:type, "type").transform_keys(&:to_sym)
      else
        {}
      end
    end

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

    def validate!
      raise InvalidServerNameError unless valid_name?
      raise InvalidRegistryError unless valid_registry?
      raise InvalidServerVersionError unless valid_version?
      validate_transport!
      validate_pagination!
      validate_title!
      validate_instructions!

      validate_environment_variables!
    end

    def environment_variables
      @environment_variables ||= {}
    end

    def environment_variable(key)
      environment_variables[key.to_s.upcase] || ENV[key.to_s.upcase] || nil
    end

    def require_environment_variable(key)
      required_environment_variables << key.to_s.upcase
    end

    # Programatically set an environment variable - useful if an alternative
    # to environment variables is used for security purposes. Despite being
    # more like 'configuration variables', these are called environment variables
    # to align with the Model Context Protocol terminology.
    #
    # see: https://modelcontextprotocol.io/docs/tools/debugging#environment-variables
    #
    # @param key [String] The key to set the environment variable for
    # @param value [String] The value to set the environment variable to
    def set_environment_variable(key, value)
      environment_variables[key.to_s.upcase] = value
    end

    def context
      @context ||= {}
    end

    def context=(context_hash = {})
      @context = context_hash
    end

    private

    def required_environment_variables
      @required_environment_variables ||= []
    end

    def validate_environment_variables!
      required_environment_variables.each do |key|
        raise MissingRequiredEnvironmentVariable, "#{key} is not set" unless environment_variable(key)
      end
    end

    def valid_name?
      name&.is_a?(String)
    end

    def valid_registry?
      registry&.is_a?(ModelContextProtocol::Server::Registry)
    end

    def valid_version?
      version&.is_a?(String)
    end

    def validate_transport!
      case transport_type
      when :streamable_http
        validate_streamable_http_transport!
      when :stdio, nil
        # stdio transport has no required options
      else
        raise InvalidTransportError, "Unknown transport type: #{transport_type}" if transport_type
      end
    end

    def validate_streamable_http_transport!
      options = transport_options

      unless options[:redis_client]
        raise InvalidTransportError, "streamable_http transport requires redis_client option"
      end

      redis_client = options[:redis_client]
      unless redis_client.respond_to?(:hset) && redis_client.respond_to?(:expire)
        raise InvalidTransportError, "redis_client must be a Redis-compatible client"
      end
    end

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

    def validate_title!
      return if title.nil?
      return if title.is_a?(String)

      raise InvalidServerTitleError, "Server title must be a string"
    end

    def validate_instructions!
      return if instructions.nil?
      return if instructions.is_a?(String)

      raise InvalidServerInstructionsError, "Server instructions must be a string"
    end
  end
end
