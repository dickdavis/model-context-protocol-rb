module ModelContextProtocol
  class Server::Configuration
    # Raised when configured with invalid name.
    class InvalidServerNameError < StandardError; end

    # Raised when configured with invalid version.
    class InvalidServerVersionError < StandardError; end

    # Raised when configured with invalid registry.
    class InvalidRegistryError < StandardError; end

    attr_accessor :enable_log, :name, :registry, :version

    def logging_enabled?
      enable_log || false
    end

    def validate!
      raise InvalidServerNameError unless valid_name?
      raise InvalidRegistryError unless valid_registry?
      raise InvalidServerVersionError unless valid_version?
    end

    private

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
