module ModelContextProtocol
  class Server::Prompt
    include ModelContextProtocol::Server::Cancellable
    include ModelContextProtocol::Server::ContentHelpers
    include ModelContextProtocol::Server::Progressable

    attr_reader :arguments, :context, :client_logger, :server_logger

    def initialize(arguments, client_logger, server_logger, context = {})
      validate!(arguments)
      @arguments = arguments
      @context = context
      @client_logger = client_logger
      @server_logger = server_logger
    end

    def call
      raise NotImplementedError, "Subclasses must implement the call method"
    end

    Response = Data.define(:messages, :description, :title) do
      def serialized
        result = {description:, messages:}
        result[:title] = title if title
        result
      end
    end
    private_constant :Response

    def message_history(&block)
      builder = MessageHistoryBuilder.new(self)
      builder.instance_eval(&block)
      builder.messages
    end

    private def respond_with(messages:)
      Response[messages:, description: self.class.description, title: self.class.title]
    end

    private def validate!(arguments = {})
      defined_arguments = self.class.defined_arguments || []
      required_args = defined_arguments.select { |arg| arg[:required] }.map { |arg| arg[:name].to_sym }
      valid_arg_names = defined_arguments.map { |arg| arg[:name].to_sym }

      missing_args = required_args - arguments.keys
      unless missing_args.empty?
        missing_args_list = missing_args.join(", ")
        raise ArgumentError, "Missing required arguments: #{missing_args_list}"
      end

      extra_args = arguments.keys - valid_arg_names
      unless extra_args.empty?
        extra_args_list = extra_args.join(", ")
        raise ArgumentError, "Unexpected arguments: #{extra_args_list}"
      end
    end

    class << self
      attr_reader :name, :description, :title, :defined_arguments

      def define(&block)
        @defined_arguments ||= []

        definition_dsl = DefinitionDSL.new
        definition_dsl.instance_eval(&block)

        @name = definition_dsl.name
        @description = definition_dsl.description
        @title = definition_dsl.title
        @defined_arguments.concat(definition_dsl.arguments)
      end

      def inherited(subclass)
        subclass.instance_variable_set(:@name, @name)
        subclass.instance_variable_set(:@description, @description)
        subclass.instance_variable_set(:@title, @title)
        subclass.instance_variable_set(:@defined_arguments, @defined_arguments&.dup)
      end

      def call(arguments, client_logger, server_logger, context = {})
        new(arguments, client_logger, server_logger, context).call
      rescue ArgumentError => error
        raise ModelContextProtocol::Server::ParameterValidationError, error.message
      end

      def definition
        result = {name: @name, description: @description, arguments: @defined_arguments}
        result[:title] = @title if @title
        result
      end

      def complete_for(arg_name, value)
        arg = @defined_arguments&.find { |a| a[:name] == arg_name.to_s }
        completion = (arg && arg[:completion]) ? arg[:completion] : ModelContextProtocol::Server::NullCompletion
        completion.call(arg_name.to_s, value)
      end
    end

    class MessageHistoryBuilder
      include Server::ContentHelpers

      attr_reader :messages

      def initialize(prompt_instance)
        @messages = []
        @prompt_instance = prompt_instance
      end

      def arguments
        @prompt_instance.arguments
      end

      def context
        @prompt_instance.context
      end

      def client_logger
        @prompt_instance.client_logger
      end

      def server_logger
        @prompt_instance.server_logger
      end

      def user_message(&block)
        content = instance_eval(&block).serialized
        @messages << {
          role: "user",
          content: content
        }
      end

      def assistant_message(&block)
        content = instance_eval(&block).serialized
        @messages << {
          role: "assistant",
          content: content
        }
      end
    end

    class DefinitionDSL
      attr_reader :arguments

      def initialize
        @arguments = []
      end

      def name(value = nil)
        @name = value if value
        @name
      end

      def description(value = nil)
        @description = value if value
        @description
      end

      def title(value = nil)
        @title = value if value
        @title
      end

      def argument(&block)
        argument_dsl = ArgumentDSL.new
        argument_dsl.instance_eval(&block)

        @arguments << {
          name: argument_dsl.name,
          description: argument_dsl.description,
          required: argument_dsl.required,
          completion: argument_dsl.completion
        }
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

      def completion(klass_or_values = nil)
        unless klass_or_values.nil?
          @completion = if klass_or_values.is_a?(Array)
            create_array_completion(klass_or_values)
          else
            klass_or_values
          end
        end
        @completion
      end

      private

      def create_array_completion(values)
        ModelContextProtocol::Server::Completion.define do
          filtered_values = values.grep(/#{argument_value}/)
          respond_with values: filtered_values
        end
      end
    end
  end
end
