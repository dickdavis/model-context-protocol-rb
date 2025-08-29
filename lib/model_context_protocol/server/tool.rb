require "json-schema"

module ModelContextProtocol
  class Server::Tool
    attr_reader :params, :context

    def initialize(params, context = {})
      validate!(params)
      @params = params
      @context = context
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

    ResourceResponse = Data.define(:uri, :text, :mime_type) do
      def initialize(uri:, text:, mime_type: "text/plain")
        super
      end

      def serialized
        {content: [{type: "resource", resource: {uri:, mimeType: mime_type, text:}}], isError: false}
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
      in [:resource, {mime_type:, text:, uri:}]
        ResourceResponse[mime_type:, text:, uri:]
      in [:resource, {text:, uri:}]
        ResourceResponse[text:, uri:]
      in [:error, {text:}]
        ToolErrorResponse[text:]
      else
        raise ModelContextProtocol::Server::ResponseArgumentsError, "Invalid arguments: #{type}, #{options}"
      end
    end

    private def validate!(params)
      JSON::Validator.validate!(self.class.input_schema, params)
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

      def call(params, context = {})
        new(params, context).call
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
