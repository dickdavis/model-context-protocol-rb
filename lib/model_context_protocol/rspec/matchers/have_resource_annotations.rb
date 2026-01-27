# frozen_string_literal: true

module ModelContextProtocol
  module RSpec
    module Matchers
      # Matcher that validates a resource response has specific annotations.
      #
      # @example Basic usage
      #   expect(response).to have_resource_annotations(priority: 0.9)
      #
      # @example With audience
      #   expect(response).to have_resource_annotations(audience: ["user", "assistant"])
      #
      # @example With multiple annotations
      #   expect(response).to have_resource_annotations(priority: 0.9, audience: ["user"])
      #
      def have_resource_annotations(expected_annotations)
        HaveResourceAnnotations.new(expected_annotations)
      end

      class HaveResourceAnnotations
        def initialize(expected_annotations)
          @expected_annotations = expected_annotations
          @failure_reasons = []
        end

        def matches?(actual)
          @actual = actual
          @failure_reasons = []
          @serialized = serialize_response(actual)

          return false if @serialized.nil?

          validate_has_contents &&
            validate_has_annotations
        end

        def failure_message
          "expected resource response to have annotations matching #{@expected_annotations.inspect}, but:\n" +
            @failure_reasons.map { |reason| "  - #{reason}" }.join("\n")
        end

        def failure_message_when_negated
          "expected resource response not to have annotations matching #{@expected_annotations.inspect}, but it did"
        end

        def description
          "have resource annotations matching #{@expected_annotations.inspect}"
        end

        private

        def serialize_response(response)
          if response.respond_to?(:serialized)
            response.serialized
          elsif response.is_a?(Hash)
            response
          else
            @failure_reasons << "response must respond to :serialized or be a Hash"
            nil
          end
        end

        def validate_has_contents
          @contents = @serialized[:contents] || @serialized["contents"]

          unless @contents
            @failure_reasons << "response does not have :contents key"
            return false
          end

          unless @contents.is_a?(Array)
            @failure_reasons << "contents must be an Array"
            return false
          end

          true
        end

        def validate_has_annotations
          items_with_annotations = @contents.select do |content|
            content.key?(:annotations) || content.key?("annotations")
          end

          if items_with_annotations.empty?
            @failure_reasons << "no content with annotations found in resource response"
            return false
          end

          matching_item = items_with_annotations.find do |content|
            annotations = content[:annotations] || content["annotations"]
            annotations_match?(annotations)
          end

          unless matching_item
            @failure_reasons << "no content with matching annotations found"
            return false
          end

          true
        end

        def annotations_match?(annotations)
          return false unless annotations.is_a?(Hash)

          @expected_annotations.all? do |key, expected_value|
            # Handle both symbol and string keys, and camelCase conversion
            actual_value = get_annotation_value(annotations, key)
            actual_value == expected_value
          end
        end

        def get_annotation_value(annotations, key)
          # Try symbol key
          return annotations[key] if annotations.key?(key)

          # Try string key
          string_key = key.to_s
          return annotations[string_key] if annotations.key?(string_key)

          # Try camelCase conversion (e.g., :last_modified -> :lastModified)
          camel_key = to_camel_case(key)
          return annotations[camel_key] if annotations.key?(camel_key)
          return annotations[camel_key.to_s] if annotations.key?(camel_key.to_s)

          nil
        end

        def to_camel_case(key)
          key.to_s.gsub(/_([a-z])/) { $1.upcase }.to_sym
        end
      end
    end
  end
end
