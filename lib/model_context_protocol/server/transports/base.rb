module ModelContextProtocol
  module Server::Transports
    class Base
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

      attr_reader :logger, :router

      def initialize(logger:, router:)
        @logger = logger
        @router = router
      end

      def begin
        loop do
          line = receive_message
          break unless line

          begin
            message = JSON.parse(line.chomp)
            next if message["method"].start_with?("notifications")

            result = router.route(message)
            send_message(Response[id: message["id"], result: result.serialized])
          rescue ModelContextProtocol::Server::ParameterValidationError => validation_error
            log("Validation error: #{validation_error.message}")
            send_message(
              ErrorResponse[id: message["id"], error: {code: -32602, message: validation_error.message}]
            )
          rescue JSON::ParserError => parser_error
            log("Parser error: #{parser_error.message}")
            send_message(
              ErrorResponse[id: "", error: {code: -32700, message: parser_error.message}]
            )
          rescue => error
            log("Internal error: #{error.message}")
            log(error.backtrace)
            send_message(
              ErrorResponse[id: message["id"], error: {code: -32603, message: error.message}]
            )
          end
        end
      end

      private

      def log(output, level = :error)
        logger.send(level.to_sym, output)
      end

      def receive_message
        raise NotImplementedError, "subclasses must implement `receive_message`"
      end

      def send_message(_message)
        raise NotImplementedError, "subclasses must implement `send_message`"
      end
    end
  end
end
