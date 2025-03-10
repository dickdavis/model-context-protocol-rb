require "json"

module ModelContextProtocol
  class Server
    # Raised when invalid parameters are provided.
    class ParameterValidationError < StandardError; end

    class Configuration
      attr_accessor :enable_log, :name, :router, :version

      def logging_enabled?
        enable_log || false
      end

      def validate!
        raise InvalidServerNameError unless valid_name?
        raise InvalidRouterError unless valid_router?
        raise InvalidServerVersionError unless valid_version?
      end

      private

      def valid_name?
        true
      end

      def valid_router?
        true
      end

      def valid_version?
        true
      end
    end

    PROTOCOL_VERSION = "2024-11-05".freeze

    attr_reader :configuration

    def initialize
      @configuration = Configuration.new
      yield(@configuration) if block_given?
      @configuration.router.server = self if @configuration.router
    end

    def start
      log("Server starting")

      configuration.validate!

      loop do
        line = $stdin.gets
        break unless line

        message = JSON.parse(line.chomp)
        log("Received message: #{message.inspect}")

        response = configuration.router.route(message)
        send_response(message["id"], response) if response
      end
    rescue ModelContextProtocol::Server::ParameterValidationError => error
      send_error_response(message["id"], {code: -32602, message: error.message})
    rescue => e
      log("Error: #{e.message}")
      log(e.backtrace)
    end

    private

    def log(output)
      warn(output) if configuration.logging_enabled?
    end

    def send_response(id, result)
      response = {jsonrpc: "2.0", id:, result:}
      $stdout.puts(JSON.generate(response))
      $stdout.flush
    end

    def send_error_response(id, error)
      response = {jsonrpc: "2.0", id:, error:}
      $stdout.puts(JSON.generate(response))
      $stdout.flush
    end
  end
end
