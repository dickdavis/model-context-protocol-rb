require "json-schema"

module ModelContextProtocol
  class Server::Prompt
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

    PromptErrorResponse = Data.define(:text) do
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
        response = new(params).call
        response.serialized
      rescue ArgumentError => error
        raise ModelContextProtocol::Server::ParameterValidationError, error.message
      rescue => error
        PromptErrorResponse[text: error.message].serialized
      end

      def metadata
        {name: @name, description: @description, arguments: @arguments}
      end
    end
  end
end
