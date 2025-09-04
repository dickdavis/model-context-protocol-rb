require "json-schema"

module ModelContextProtocol
  class Server::Tool
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

    TextResponse = Data.define(:text) do
      def serialized
        {content: [{type: "text", text:}], isError: false}
      end
    end
    private_constant :TextResponse

    ImageResponse = Data.define(:data, :mime_type) do
      def initialize(data:, mime_type: "image/png")
        super
      end

      def serialized
        {content: [{type: "image", data:, mimeType: mime_type}], isError: false}
      end
    end
    private_constant :ImageResponse

    ResourceResponse = Data.define(:resource_klass) do
      def serialized
        resource_data = resource_klass.call
        {content: [{type: "resource", resource: resource_data.serialized[:contents].first}], isError: false}
      end
    end
    private_constant :ResourceResponse

    ToolErrorResponse = Data.define(:text) do
      def serialized
        {content: [{type: "text", text:}], isError: true}
      end
    end
    private_constant :ToolErrorResponse

    private def respond_with(type, **options)
      case [type, options]
      in [:text, {text:}]
        TextResponse[text:]
      in [:image, {data:, mime_type:}]
        ImageResponse[data:, mime_type:]
      in [:image, {data:}]
        ImageResponse[data:]
      in [:resource, {resource:}]
        ResourceResponse[resource_klass: resource]
      in [:error, {text:}]
        ToolErrorResponse[text:]
      else
        raise ModelContextProtocol::Server::ResponseArgumentsError, "Invalid arguments: #{type}, #{options}"
      end
    end

    private def validate!(arguments)
      JSON::Validator.validate!(self.class.input_schema, arguments)
    end

    class << self
      attr_reader :name, :description, :input_schema

      def with_metadata(&block)
        metadata_dsl = MetadataDSL.new
        metadata_dsl.instance_eval(&block)

        @name = metadata_dsl.name
        @description = metadata_dsl.description
        @input_schema = metadata_dsl.input_schema
      end

      def inherited(subclass)
        subclass.instance_variable_set(:@name, @name)
        subclass.instance_variable_set(:@description, @description)
        subclass.instance_variable_set(:@input_schema, @input_schema)
      end

      def call(arguments, logger, context = {})
        new(arguments, logger, context).call
      rescue JSON::Schema::ValidationError => validation_error
        raise ModelContextProtocol::Server::ParameterValidationError, validation_error.message
      rescue ModelContextProtocol::Server::ResponseArgumentsError => response_arguments_error
        raise response_arguments_error
      rescue => error
        ToolErrorResponse[text: error.message]
      end

      def metadata
        {name: @name, description: @description, inputSchema: @input_schema}
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

      def input_schema(&block)
        @input_schema = instance_eval(&block) if block_given?
        @input_schema
      end
    end
  end
end
