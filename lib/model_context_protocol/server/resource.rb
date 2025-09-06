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
        content = {mimeType: resource.mime_type, text:, uri: resource.uri}
        content[:title] = resource.class.title if resource.class.title
        annotations = resource.class.annotations&.serialized
        content[:annotations] = annotations if annotations
        {contents: [content]}
      end
    end
    private_constant :TextResponse

    BinaryResponse = Data.define(:blob, :resource) do
      def serialized
        content = {blob:, mimeType: resource.mime_type, uri: resource.uri}
        content[:title] = resource.class.title if resource.class.title
        annotations = resource.class.annotations&.serialized
        content[:annotations] = annotations if annotations
        {contents: [content]}
      end
    end
    private_constant :BinaryResponse

    private def respond_with(**kwargs)
      case [kwargs]
      in [{text:}]
        TextResponse[resource: self, text:]
      in [{binary:}]
        BinaryResponse[blob: binary, resource: self]
      else
        raise ModelContextProtocol::Server::ResponseArgumentsError, "Invalid arguments: #{options}"
      end
    end

    class << self
      attr_reader :name, :description, :title, :mime_type, :uri, :annotations

      def with_metadata(&block)
        metadata_dsl = MetadataDSL.new
        metadata_dsl.instance_eval(&block)

        @name = metadata_dsl.name
        @description = metadata_dsl.description
        @title = metadata_dsl.title
        @mime_type = metadata_dsl.mime_type
        @uri = metadata_dsl.uri
        @annotations = metadata_dsl.defined_annotations
      end

      def inherited(subclass)
        subclass.instance_variable_set(:@name, @name)
        subclass.instance_variable_set(:@description, @description)
        subclass.instance_variable_set(:@title, @title)
        subclass.instance_variable_set(:@mime_type, @mime_type)
        subclass.instance_variable_set(:@uri, @uri)
        subclass.instance_variable_set(:@annotations, @annotations&.dup)
      end

      def call
        new.call
      end

      def metadata
        result = {name: @name, description: @description, mimeType: @mime_type, uri: @uri}
        result[:title] = @title if @title
        result[:annotations] = @annotations.serialized if @annotations
        result
      end
    end

    class MetadataDSL
      attr_reader :defined_annotations

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

      def mime_type(value = nil)
        @mime_type = value if value
        @mime_type
      end

      def uri(value = nil)
        @uri = value if value
        @uri
      end

      def annotations(&block)
        @defined_annotations = AnnotationsDSL.new
        @defined_annotations.instance_eval(&block)
        @defined_annotations
      end
    end

    class AnnotationsDSL
      VALID_AUDIENCE_VALUES = [:user, :assistant].freeze

      def initialize
        @audience = nil
        @priority = nil
        @last_modified = nil
      end

      def audience(value)
        normalized_value = Array(value).map(&:to_sym)
        invalid_values = normalized_value - VALID_AUDIENCE_VALUES
        unless invalid_values.empty?
          raise ArgumentError, "Invalid audience values: #{invalid_values.join(", ")}. Valid values are: #{VALID_AUDIENCE_VALUES.join(", ")}"
        end
        @audience = normalized_value.map(&:to_s)
      end

      def priority(value)
        unless value.is_a?(Numeric) && value >= 0.0 && value <= 1.0
          raise ArgumentError, "Priority must be a number between 0.0 and 1.0, got: #{value}"
        end
        @priority = value.to_f
      end

      def last_modified(value)
        # Validate ISO 8601 format
        begin
          Time.iso8601(value)
        rescue ArgumentError
          raise ArgumentError, "lastModified must be in ISO 8601 format (e.g., '2025-01-12T15:00:58Z'), got: #{value}"
        end
        @last_modified = value
      end

      def serialized
        result = {}
        result[:audience] = @audience if @audience
        result[:priority] = @priority if @priority
        result[:lastModified] = @last_modified if @last_modified
        result.empty? ? nil : result
      end
    end
  end
end
