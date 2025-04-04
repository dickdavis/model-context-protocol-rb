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
        metadata = instance_eval(&block)

        @name = metadata[:name]
        @description = metadata[:description]
        @mime_type = metadata[:mime_type]
        @uri = metadata[:uri]
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
        {name: @name, description: @description, mime_type: @mime_type, uri: @uri}
      end
    end
  end
end
