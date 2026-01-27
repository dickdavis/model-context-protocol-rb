# frozen_string_literal: true

module ModelContextProtocol
  module RSpec
    module Matchers
      # Matcher that validates a tool response contains specific structured content.
      #
      # @example Basic usage
      #   expect(response).to have_structured_content(temperature: 22.5)
      #
      # @example With nested content
      #   expect(response).to have_structured_content(user: {name: "John", age: 30})
      #
      def have_structured_content(expected_content)
        HaveStructuredContent.new(expected_content)
      end

      class HaveStructuredContent
        def initialize(expected_content)
          @expected_content = expected_content
          @failure_reasons = []
        end

        def matches?(actual)
          @actual = actual
          @failure_reasons = []
          @serialized = serialize_response(actual)

          return false if @serialized.nil?

          validate_has_structured_content &&
            validate_content_matches
        end

        def failure_message
          "expected response to have structured content matching #{@expected_content.inspect}, but:\n" +
            @failure_reasons.map { |reason| "  - #{reason}" }.join("\n")
        end

        def failure_message_when_negated
          "expected response not to have structured content matching #{@expected_content.inspect}, but it did"
        end

        def description
          "have structured content matching #{@expected_content.inspect}"
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

        def validate_has_structured_content
          @structured_content = @serialized[:structuredContent] || @serialized["structuredContent"]

          unless @structured_content
            @failure_reasons << "response does not have :structuredContent key"
            return false
          end

          true
        end

        def validate_content_matches
          @expected_content.each do |key, expected_value|
            actual_value = @structured_content[key] || @structured_content[key.to_s]

            if actual_value.nil? && !@structured_content.key?(key) && !@structured_content.key?(key.to_s)
              @failure_reasons << "missing key :#{key}"
            elsif actual_value != expected_value
              @failure_reasons << "expected :#{key} to be #{expected_value.inspect}, got #{actual_value.inspect}"
            end
          end

          @failure_reasons.empty?
        end
      end
    end
  end
end
