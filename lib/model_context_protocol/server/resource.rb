module ModelContextProtocol
  class Server::Resource
    attr_reader :mime_type, :uri

    def initialize
      @mime_type = self.class.mime_type
      @uri = self.class.uri
    end

    def call
      raise NotImplementedError, "Subclasses must implement the call method"
    end

    TextResponse = Data.define(:resource, :text) do
      def serialized
        {contents: [{mimeType: resource.mime_type, text:, uri: resource.uri}]}
      end
    end
    private_constant :TextResponse

    BinaryResponse = Data.define(:blob, :resource) do
      def serialized
        {contents: [{blob:, mimeType: resource.mime_type, uri: resource.uri}]}
      end
    end
    private_constant :BinaryResponse

    private def respond_with(type, **options)
      case [type, options]
      in [:text, {text:}]
        TextResponse[resource: self, text:]
      in [:binary, {blob:}]
        BinaryResponse[blob:, resource: self]
      else
        raise ModelContextProtocol::Server::ResponseArgumentsError, "Invalid arguments: #{type}, #{options}"
      end
    end

    class << self
      attr_reader :name, :description, :mime_type, :uri

      def with_metadata(&block)
        metadata_dsl = MetadataDSL.new
        metadata_dsl.instance_eval(&block)

        @name = metadata_dsl.name
        @description = metadata_dsl.description
        @mime_type = metadata_dsl.mime_type
        @uri = metadata_dsl.uri
      end

      def inherited(subclass)
        subclass.instance_variable_set(:@name, @name)
        subclass.instance_variable_set(:@description, @description)
        subclass.instance_variable_set(:@mime_type, @mime_type)
        subclass.instance_variable_set(:@uri, @uri)
      end

      def call
        new.call
      end

      def metadata
        {name: @name, description: @description, mimeType: @mime_type, uri: @uri}
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

      def mime_type(value = nil)
        @mime_type = value if value
        @mime_type
      end

      def uri(value = nil)
        @uri = value if value
        @uri
      end
    end
  end
end
