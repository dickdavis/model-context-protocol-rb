require "json-schema"

module ModelContextProtocol
  class Server::Tool
    include ModelContextProtocol::Server::ContentHelpers

    attr_reader :arguments, :context, :logger

    def initialize(arguments, logger, context = {})
      validate!(arguments)
      @arguments = arguments
      @context = context
      @logger = logger
    end

    def call
      raise NotImplementedError, "Subclasses must implement the call method"
    end

    Response = Data.define(:content) do
      def serialized
        serialized_contents = content.map(&:serialized)
        {content: serialized_contents, isError: false}
      end
    end
    private_constant :Response

    ErrorResponse = Data.define(:error) do
      def serialized
        {content: [{type: "text", text: error}], isError: true}
      end
    end
    private_constant :ErrorResponse

    private def respond_with(**kwargs)
      case [kwargs]
      in [{content:}]
        content_array = content.is_a?(Array) ? content : [content]
        Response[content: content_array]
      in [{error:}]
        ErrorResponse[error:]
      else
        raise ModelContextProtocol::Server::ResponseArgumentsError, "Invalid arguments: #{kwargs.inspect}"
      end
    end

    private def validate!(arguments)
      JSON::Validator.validate!(self.class.input_schema, arguments)
    end

    class << self
      attr_reader :name, :description, :title, :input_schema

      def with_metadata(&block)
        metadata_dsl = MetadataDSL.new
        metadata_dsl.instance_eval(&block)

        @name = metadata_dsl.name
        @description = metadata_dsl.description
        @title = metadata_dsl.title
        @input_schema = metadata_dsl.input_schema
      end

      def inherited(subclass)
        subclass.instance_variable_set(:@name, @name)
        subclass.instance_variable_set(:@description, @description)
        subclass.instance_variable_set(:@title, @title)
        subclass.instance_variable_set(:@input_schema, @input_schema)
      end

      def call(arguments, logger, context = {})
        new(arguments, logger, context).call
      rescue JSON::Schema::ValidationError => validation_error
        raise ModelContextProtocol::Server::ParameterValidationError, validation_error.message
      rescue ModelContextProtocol::Server::ResponseArgumentsError => response_arguments_error
        raise response_arguments_error
      rescue => error
        ErrorResponse[error: error.message]
      end

      def metadata
        result = {name: @name, description: @description, inputSchema: @input_schema}
        result[:title] = @title if @title
        result
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

      def title(value = nil)
        @title = value if value
        @title
      end

      def input_schema(&block)
        @input_schema = instance_eval(&block) if block_given?
        @input_schema
      end
    end
  end
end
