module ModelContextProtocol
  module Server::Transports
    class Stdio < Base
      private

      def log(output, level = :error)
        logger.send(level.to_sym, output)
      end

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
end
