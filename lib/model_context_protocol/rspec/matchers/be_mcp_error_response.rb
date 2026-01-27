# frozen_string_literal: true

module ModelContextProtocol
  module RSpec
    module Matchers
      # Matcher that validates a tool response is an error response.
      #
      # @example Basic usage (any error)
      #   expect(response).to be_mcp_error_response
      #
      # @example With message match (string)
      #   expect(response).to be_mcp_error_response("Connection timed out")
      #
      # @example With message match (regex)
      #   expect(response).to be_mcp_error_response(/failed.*timeout/i)
      #
      def be_mcp_error_response(expected_message = nil)
        BeMcpErrorResponse.new(expected_message)
      end

      class BeMcpErrorResponse
        def initialize(expected_message = nil)
          @expected_message = expected_message
          @failure_reasons = []
        end

        def matches?(actual)
          @actual = actual
          @failure_reasons = []
          @serialized = serialize_response(actual)

          return false if @serialized.nil?

          validate_is_error &&
            validate_error_message
        end

        def failure_message
          constraint = @expected_message ? " with message matching #{@expected_message.inspect}" : ""
          "expected response to be an MCP error response#{constraint}, but:\n" +
            @failure_reasons.map { |reason| "  - #{reason}" }.join("\n")
        end

        def failure_message_when_negated
          constraint = @expected_message ? " with message matching #{@expected_message.inspect}" : ""
          "expected response not to be an MCP error response#{constraint}, but it was"
        end

        def description
          constraint = @expected_message ? " with message matching #{@expected_message.inspect}" : ""
          "be an MCP error response#{constraint}"
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

        def validate_is_error
          is_error = @serialized[:isError] || @serialized["isError"]

          unless is_error == true
            @failure_reasons << "isError is not true (got: #{is_error.inspect})"
            return false
          end

          true
        end

        def validate_error_message
          return true unless @expected_message

          content = @serialized[:content] || @serialized["content"]

          unless content
            @failure_reasons << "response does not have :content key"
            return false
          end

          text_items = content.select do |item|
            type = item[:type] || item["type"]
            type == "text"
          end

          if text_items.empty?
            @failure_reasons << "no text content found in error response"
            return false
          end

          matching_item = text_items.find do |item|
            text = item[:text] || item["text"]
            message_matches?(text)
          end

          unless matching_item
            actual_texts = text_items.map { |item| item[:text] || item["text"] }
            @failure_reasons << "no error message matched #{@expected_message.inspect}, found: #{actual_texts.inspect}"
            return false
          end

          true
        end

        def message_matches?(text)
          case @expected_message
          when Regexp
            @expected_message.match?(text)
          else
            text.include?(@expected_message.to_s)
          end
        end
      end
    end
  end
end
