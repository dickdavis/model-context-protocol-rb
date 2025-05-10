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
      attr_reader :name, :description, :mime_type, :uri_template, :completions

      def with_metadata(&block)
        metadata_dsl = MetadataDSL.new
        metadata_dsl.instance_eval(&block)

        @name = metadata_dsl.name
        @description = metadata_dsl.description
        @mime_type = metadata_dsl.mime_type
        @uri_template = metadata_dsl.uri_template
        @completions = metadata_dsl.completions
      end

      def inherited(subclass)
        subclass.instance_variable_set(:@name, @name)
        subclass.instance_variable_set(:@description, @description)
        subclass.instance_variable_set(:@mime_type, @mime_type)
        subclass.instance_variable_set(:@uri_template, @uri_template)
        subclass.instance_variable_set(:@completions, @completions&.dup)
      end

      def call(uri)
        new(uri).call
      end

      def complete_for(param_name, value)
        completion = if @completions && @completions[param_name.to_s]
          @completions[param_name.to_s]
        else
          ModelContextProtocol::Server::NullCompletion
        end

        completion.call(param_name.to_s, value)
      end

      def metadata
        {
          name: @name,
          description: @description,
          mimeType: @mime_type,
          uriTemplate: @uri_template,
          completions: @completions&.transform_keys(&:to_s)
        }
      end
    end

    class MetadataDSL
      attr_reader :completions

      def initialize
        @completions = {}
      end

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

      def uri_template(value = nil, &block)
        @uri_template = value if value

        if block_given?
          completion_dsl = CompletionDSL.new
          completion_dsl.instance_eval(&block)
          @completions = completion_dsl.completions
        end

        @uri_template
      end
    end

    class CompletionDSL
      attr_reader :completions

      def initialize
        @completions = {}
      end

      def completion(param_name, completion_class)
        @completions[param_name.to_s] = completion_class
      end
    end
  end
end
