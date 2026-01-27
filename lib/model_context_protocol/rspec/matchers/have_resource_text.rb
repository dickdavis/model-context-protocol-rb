# frozen_string_literal: true

module ModelContextProtocol
  module RSpec
    module Matchers
      # Matcher that validates a resource response contains specific text content.
      #
      # @example With exact string match
      #   expect(response).to have_resource_text("Hello, World!")
      #
      # @example With regex match
      #   expect(response).to have_resource_text(/secret.*plans/i)
      #
      def have_resource_text(expected_text)
        HaveResourceText.new(expected_text)
      end

      class HaveResourceText
        def initialize(expected_text)
          @expected_text = expected_text
          @failure_reasons = []
        end

        def matches?(actual)
          @actual = actual
          @failure_reasons = []
          @serialized = serialize_response(actual)

          return false if @serialized.nil?

          validate_has_contents &&
            validate_has_text
        end

        def failure_message
          "expected resource response to have text matching #{@expected_text.inspect}, but:\n" +
            @failure_reasons.map { |reason| "  - #{reason}" }.join("\n")
        end

        def failure_message_when_negated
          "expected resource response not to have text matching #{@expected_text.inspect}, but it did"
        end

        def description
          "have resource text matching #{@expected_text.inspect}"
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

        def validate_has_text
          text_items = @contents.select do |content|
            content.key?(:text) || content.key?("text")
          end

          if text_items.empty?
            @failure_reasons << "no text content found in resource response"
            return false
          end

          matching_item = text_items.find do |content|
            text = content[:text] || content["text"]
            text_matches?(text)
          end

          unless matching_item
            actual_texts = text_items.map { |c| c[:text] || c["text"] }
            @failure_reasons << "no text content matched, found: #{actual_texts.inspect}"
            return false
          end

          true
        end

        def text_matches?(text)
          case @expected_text
          when Regexp
            @expected_text.match?(text)
          else
            text.include?(@expected_text.to_s)
          end
        end
      end
    end
  end
end
