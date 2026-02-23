require "json-schema"

module ModelContextProtocol
  class Server::Tool
    # Raised when output schema validation fails.
    class OutputSchemaValidationError < StandardError; end

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

    Response = Data.define(:content) do
      def serialized
        serialized_contents = content.map(&:serialized)
        {content: serialized_contents, isError: false}
      end
    end
    private_constant :Response

    StructuredContentResponse = Data.define(:structured_content, :tool) do
      def serialized
        json_text = JSON.generate(structured_content)
        text_content = ModelContextProtocol::Server::Content::Text[
          meta: nil,
          annotations: nil,
          text: json_text
        ]

        validation_errors = JSON::Validator.fully_validate(
          tool.class.definition[:outputSchema], structured_content
        )

        if validation_errors.empty?
          {
            structuredContent: structured_content,
            content: [text_content.serialized],
            isError: false
          }
        else
          raise OutputSchemaValidationError, validation_errors.join(", ")
        end
      end
    end
    private_constant :StructuredContentResponse

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
      in [{structured_content:}]
        StructuredContentResponse[structured_content:, tool: self]
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
      attr_reader :name, :description, :title, :input_schema, :output_schema, :annotations

      def define(&block)
        definition_dsl = DefinitionDSL.new
        definition_dsl.instance_eval(&block)

        @name = definition_dsl.name
        @description = definition_dsl.description
        @title = definition_dsl.title
        @input_schema = definition_dsl.input_schema
        @output_schema = definition_dsl.output_schema
        @annotations = definition_dsl.annotations
      end

      def inherited(subclass)
        subclass.instance_variable_set(:@name, @name)
        subclass.instance_variable_set(:@description, @description)
        subclass.instance_variable_set(:@title, @title)
        subclass.instance_variable_set(:@input_schema, @input_schema)
        subclass.instance_variable_set(:@output_schema, @output_schema)
        subclass.instance_variable_set(:@annotations, @annotations)
      end

      def call(arguments, client_logger, server_logger, context = {})
        new(arguments, client_logger, server_logger, context).call
      rescue JSON::Schema::ValidationError => validation_error
        raise ModelContextProtocol::Server::ParameterValidationError, validation_error.message
      rescue OutputSchemaValidationError, ModelContextProtocol::Server::ResponseArgumentsError => tool_error
        raise tool_error, tool_error.message
      rescue Server::Cancellable::CancellationError
        raise
      rescue => error
        ErrorResponse[error: error.message]
      end

      def definition
        result = {name: @name, description: @description, inputSchema: @input_schema}
        result[:title] = @title if @title
        result[:outputSchema] = @output_schema if @output_schema
        result[:annotations] = @annotations if @annotations
        result
      end
    end

    class DefinitionDSL
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

      def output_schema(&block)
        @output_schema = instance_eval(&block) if block_given?
        @output_schema
      end

      def annotations(&block)
        @annotations = instance_eval(&block) if block_given?
        @annotations
      end
    end
  end
end
