module ModelContextProtocol
  class Server::Configuration
    # Raised when configured with invalid name.
    class InvalidServerNameError < StandardError; end

    # Raised when configured with invalid version.
    class InvalidServerVersionError < StandardError; end

    # Raised when configured with invalid registry.
    class InvalidRegistryError < StandardError; end

    # Raised when a required environment variable is not set
    class MissingRequiredEnvironmentVariable < StandardError; end

    attr_accessor :enable_log, :name, :registry, :version

    def logging_enabled?
      enable_log || false
    end

    def validate!
      raise InvalidServerNameError unless valid_name?
      raise InvalidRegistryError unless valid_registry?
      raise InvalidServerVersionError unless valid_version?

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
  end
end
