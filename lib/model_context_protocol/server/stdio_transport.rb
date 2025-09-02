module ModelContextProtocol
  class Server::StdioTransport
    Response = Data.define(:id, :result) do
      def serialized
        {jsonrpc: "2.0", id:, result:}
      end
    end

    ErrorResponse = Data.define(:id, :error) do
      def serialized
        {jsonrpc: "2.0", id:, error:}
      end
    end

    attr_reader :router, :configuration

    def initialize(router:, configuration:)
      @router = router
      @configuration = configuration
    end

    def handle
      # Connect logger to transport
      @configuration.logger.connect_transport(self)

      loop do
        line = receive_message
        break unless line

        begin
          message = JSON.parse(line.chomp)
          next if message["method"].start_with?("notifications")

          result = router.route(message)
          send_message(Response[id: message["id"], result: result.serialized])
        rescue ModelContextProtocol::Server::ParameterValidationError => validation_error
          @configuration.logger.error("Validation error", error: validation_error.message)
          send_message(
            ErrorResponse[id: message["id"], error: {code: -32602, message: validation_error.message}]
          )
        rescue JSON::ParserError => parser_error
          @configuration.logger.error("Parser error", error: parser_error.message)
          send_message(
            ErrorResponse[id: "", error: {code: -32700, message: parser_error.message}]
          )
        rescue => error
          @configuration.logger.error("Internal error", error: error.message, backtrace: error.backtrace.first(5))
          send_message(
            ErrorResponse[id: message["id"], error: {code: -32603, message: error.message}]
          )
        end
      end
    end

    def send_notification(method, params)
      notification = {
        jsonrpc: "2.0",
        method: method,
        params: params
      }
      $stdout.puts(JSON.generate(notification))
      $stdout.flush
    rescue IOError => e
      # Handle broken pipe gracefully
      @configuration.logger.debug("Failed to send notification", error: e.message) if @configuration.logging_enabled?
    end

    private

    def receive_message
      $stdin.gets
    end

    def send_message(message)
      message_json = JSON.generate(message.serialized)
      $stdout.puts(message_json)
      $stdout.flush
    end
  end
end
