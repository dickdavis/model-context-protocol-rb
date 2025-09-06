module ModelContextProtocol
  class Server::ResourceTemplate
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

      def completion(param_name, completion_class_or_values)
        @completions[param_name.to_s] = if completion_class_or_values.is_a?(Array)
          create_array_completion(completion_class_or_values)
        else
          completion_class_or_values
        end
      end

      private

      def create_array_completion(values)
        ModelContextProtocol::Server::Completion.define do
          filtered_values = values.grep(/#{argument_value}/)
          respond_with values: filtered_values
        end
      end
    end
  end
end
