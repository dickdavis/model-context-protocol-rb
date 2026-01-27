# frozen_string_literal: true

module ModelContextProtocol
  module RSpec
    module Matchers
      # Matcher that validates a tool response contains specific text content.
      #
      # @example With exact string match
      #   expect(response).to have_text_content("Hello, World!")
      #
      # @example With regex match
      #   expect(response).to have_text_content(/doubled is \d+/)
      #
      def have_text_content(expected_text)
        HaveTextContent.new(expected_text)
      end

      class HaveTextContent
        def initialize(expected_text)
          @expected_text = expected_text
          @failure_reasons = []
        end

        def matches?(actual)
          @actual = actual
          @failure_reasons = []
          @serialized = serialize_response(actual)

          return false if @serialized.nil?

          validate_has_content &&
            validate_has_text_content
        end

        def failure_message
          "expected response to have text content matching #{@expected_text.inspect}, but:\n" +
            @failure_reasons.map { |reason| "  - #{reason}" }.join("\n")
        end

        def failure_message_when_negated
          "expected response not to have text content matching #{@expected_text.inspect}, but it did"
        end

        def description
          "have text content matching #{@expected_text.inspect}"
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

        def validate_has_content
          @content = @serialized[:content] || @serialized["content"]

          unless @content
            @failure_reasons << "response does not have :content key"
            return false
          end

          unless @content.is_a?(Array)
            @failure_reasons << "content must be an Array"
            return false
          end

          true
        end

        def validate_has_text_content
          text_items = @content.select do |item|
            type = item[:type] || item["type"]
            type == "text"
          end

          if text_items.empty?
            @failure_reasons << "no text content found in response"
            return false
          end

          matching_item = text_items.find do |item|
            text = item[:text] || item["text"]
            text_matches?(text)
          end

          unless matching_item
            actual_texts = text_items.map { |item| item[:text] || item["text"] }
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
