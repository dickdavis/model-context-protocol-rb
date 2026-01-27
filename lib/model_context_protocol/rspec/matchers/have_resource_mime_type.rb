# frozen_string_literal: true

module ModelContextProtocol
  module RSpec
    module Matchers
      # Matcher that validates a resource response has a specific mime type.
      #
      # @example Basic usage
      #   expect(response).to have_resource_mime_type("text/plain")
      #
      # @example With regex match
      #   expect(response).to have_resource_mime_type(/^image\//)
      #
      def have_resource_mime_type(expected_mime_type)
        HaveResourceMimeType.new(expected_mime_type)
      end

      class HaveResourceMimeType
        def initialize(expected_mime_type)
          @expected_mime_type = expected_mime_type
          @failure_reasons = []
        end

        def matches?(actual)
          @actual = actual
          @failure_reasons = []
          @serialized = serialize_response(actual)

          return false if @serialized.nil?

          validate_has_contents &&
            validate_mime_type
        end

        def failure_message
          "expected resource response to have mime type matching #{@expected_mime_type.inspect}, but:\n" +
            @failure_reasons.map { |reason| "  - #{reason}" }.join("\n")
        end

        def failure_message_when_negated
          "expected resource response not to have mime type matching #{@expected_mime_type.inspect}, but it did"
        end

        def description
          "have resource mime type matching #{@expected_mime_type.inspect}"
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

        def validate_mime_type
          matching_item = @contents.find do |content|
            mime_type = content[:mimeType] || content["mimeType"]
            mime_type_matches?(mime_type)
          end

          unless matching_item
            actual_types = @contents.map { |c| c[:mimeType] || c["mimeType"] }
            @failure_reasons << "no content with mime type matching #{@expected_mime_type.inspect}, found: #{actual_types.inspect}"
            return false
          end

          true
        end

        def mime_type_matches?(mime_type)
          case @expected_mime_type
          when Regexp
            @expected_mime_type.match?(mime_type)
          else
            mime_type == @expected_mime_type.to_s
          end
        end
      end
    end
  end
end
