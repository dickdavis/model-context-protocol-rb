module ModelContextProtocol
  class Server::Prompt
    attr_reader :params, :description

    def initialize(params)
      validate!(params)
      @description = self.class.description
      @params = params
    end

    def call
      raise NotImplementedError, "Subclasses must implement the call method"
    end

    Response = Data.define(:messages, :prompt) do
      def serialized
        {description: prompt.description, messages:}
      end
    end
    private_constant :Response

    private def respond_with(messages:)
      Response[messages:, prompt: self]
    end

    private def validate!(params = {})
      arguments = self.class.arguments || []
      required_args = arguments.select { |arg| arg[:required] }.map { |arg| arg[:name] }
      valid_arg_names = arguments.map { |arg| arg[:name] }

      missing_args = required_args - params.keys
      unless missing_args.empty?
        missing_args_list = missing_args.join(", ")
        raise ArgumentError, "Missing required arguments: #{missing_args_list}"
      end

      extra_args = params.keys - valid_arg_names
      unless extra_args.empty?
        extra_args_list = extra_args.join(", ")
        raise ArgumentError, "Unexpected arguments: #{extra_args_list}"
      end
    end

    class << self
      attr_reader :name, :description, :arguments

      def with_metadata(&block)
        metadata = instance_eval(&block)

        @name = metadata[:name]
        @description = metadata[:description]
        @arguments = metadata[:arguments]
      end

      def inherited(subclass)
        subclass.instance_variable_set(:@name, @name)
        subclass.instance_variable_set(:@description, @description)
        subclass.instance_variable_set(:@arguments, @arguments)
      end

      def call(params)
        new(params).call
      rescue ArgumentError => error
        raise ModelContextProtocol::Server::ParameterValidationError, error.message
      end

      def metadata
        {name: @name, description: @description, arguments: @arguments}
      end
    end
  end
end
