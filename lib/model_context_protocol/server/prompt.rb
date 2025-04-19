module ModelContextProtocol
  class Server::Prompt
    attr_reader :params

    def initialize(params)
      validate!(params)
      @params = params
    end

    def call
      raise NotImplementedError, "Subclasses must implement the call method"
    end

    Response = Data.define(:messages, :description) do
      def serialized
        {description:, messages:}
      end
    end
    private_constant :Response

    private def respond_with(messages:)
      Response[messages:, description: self.class.description]
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
        @arguments ||= []

        metadata_dsl = MetadataDSL.new
        metadata_dsl.instance_eval(&block)

        @name = metadata_dsl.name
        @description = metadata_dsl.description
      end

      def with_argument(&block)
        @arguments ||= []

        argument_dsl = ArgumentDSL.new
        argument_dsl.instance_eval(&block)

        @arguments << {
          name: argument_dsl.name,
          description: argument_dsl.description,
          required: argument_dsl.required,
          completion: argument_dsl.completion
        }
      end

      def inherited(subclass)
        subclass.instance_variable_set(:@name, @name)
        subclass.instance_variable_set(:@description, @description)
        subclass.instance_variable_set(:@arguments, @arguments&.dup)
      end

      def call(params)
        new(params).call
      rescue ArgumentError => error
        raise ModelContextProtocol::Server::ParameterValidationError, error.message
      end

      def metadata
        {name: @name, description: @description, arguments: @arguments}
      end

      def complete_for(arg_name, value)
        arg = @arguments&.find { |a| a[:name] == arg_name.to_s }
        completion = (arg && arg[:completion]) ? arg[:completion] : ModelContextProtocol::Server::NullCompletion
        completion.call(arg_name.to_s, value)
      end
    end

    class MetadataDSL
      def name(value = nil)
        @name = value if value
        @name
      end

      def description(value = nil)
        @description = value if value
        @description
      end
    end

    class ArgumentDSL
      def name(value = nil)
        @name = value if value
        @name
      end

      def description(value = nil)
        @description = value if value
        @description
      end

      def required(value = nil)
        @required = value unless value.nil?
        @required
      end

      def completion(klass = nil)
        @completion = klass unless klass.nil?
        @completion
      end
    end
  end
end
