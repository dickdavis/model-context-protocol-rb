require "json-schema"

module ModelContextProtocol
  class Server::Tool
    attr_reader :params

    TextResponse = Data.define(:text) do
      def serialized
        {content: [{type: "text", text:}], isError: false}
      end
    end

    ImageResponse = Data.define(:data, :mime_type) do
      def initialize(data:, mime_type: "image/png")
        super
      end

      def serialized
        {content: [{type: "image", data:, mimeType: mime_type}], isError: false}
      end
    end

    ResourceResponse = Data.define(:uri, :text, :mime_type) do
      def initialize(uri:, text:, mime_type: "text/plain")
        super
      end

      def serialized
        {content: [{type: "resource", resource: {uri:, mimeType: mime_type, text:}}], isError: false}
      end
    end

    ToolErrorResponse = Data.define(:text) do
      def serialized
        {content: [{type: "text", text:}], isError: true}
      end
    end

    def initialize(params)
      validate!(params)
      @params = params
    end

    def call
      raise NotImplementedError, "Subclasses must implement the call method"
    end

    private def validate!(params)
      JSON::Validator.validate!(self.class.input_schema, params)
    end

    class << self
      attr_reader :name, :description, :input_schema

      def with_metadata(&block)
        metadata = instance_eval(&block)

        @name = metadata[:name]
        @description = metadata[:description]
        @input_schema = metadata[:inputSchema]
      end

      def inherited(subclass)
        subclass.instance_variable_set(:@name, @name)
        subclass.instance_variable_set(:@description, @description)
        subclass.instance_variable_set(:@input_schema, @input_schema)
      end

      def call(params)
        new(params).call
      rescue JSON::Schema::ValidationError => error
        raise ModelContextProtocol::Server::ParameterValidationError, error.message
      rescue => error
        ToolErrorResponse[text: error.message]
      end

      def metadata
        {name: @name, description: @description, inputSchema: @input_schema}
      end
    end
  end
end
