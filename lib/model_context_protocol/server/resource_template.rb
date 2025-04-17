module ModelContextProtocol
  class Server::ResourceTemplate
    attr_reader :mime_type, :uri, :uri_template

    def initialize(uri)
      @mime_type = self.class.mime_type
      @uri = uri
      @uri_template = self.class.uri_template
    end

    def call
      raise NotImplementedError, "Subclasses must implement the call method"
    end

    def extracted_uri
      return @extracted_uri if defined?(@extracted_uri)

      addressable_uri = Addressable::URI.parse(uri)
      template = Addressable::Template.new(uri_template)
      @extracted_uri = template.extract(addressable_uri)
    end

    TextResponse = Data.define(:resource, :text, :uri) do
      def serialized
        {contents: [{mimeType: resource.mime_type, text:, uri:}]}
      end
    end
    private_constant :TextResponse

    BinaryResponse = Data.define(:blob, :resource, :uri) do
      def serialized
        {contents: [{blob:, mimeType: resource.mime_type, uri:}]}
      end
    end
    private_constant :BinaryResponse

    private def respond_with(type, **options)
      case [type, options]
      in [:text, {text:}]
        TextResponse[resource: self, text:, uri:]
      in [:binary, {blob:}]
        BinaryResponse[blob:, resource: self, uri:]
      else
        raise ModelContextProtocol::Server::ResponseArgumentsError, "Invalid arguments: #{type}, #{options}"
      end
    end

    class << self
      attr_reader :name, :description, :mime_type, :uri_template

      def with_metadata(&block)
        metadata = instance_eval(&block)

        @name = metadata[:name]
        @description = metadata[:description]
        @mime_type = metadata[:mime_type]
        @uri_template = metadata[:uri_template]
      end

      def inherited(subclass)
        subclass.instance_variable_set(:@name, @name)
        subclass.instance_variable_set(:@description, @description)
        subclass.instance_variable_set(:@mime_type, @mime_type)
        subclass.instance_variable_set(:@uri_template, @uri_template)
      end

      def call(uri)
        new(uri).call
      end

      def metadata
        {name: @name, description: @description, mimeType: @mime_type, uriTemplate: @uri_template}
      end
    end
  end
end
