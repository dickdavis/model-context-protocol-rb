# frozen_string_literal: true

module ModelContextProtocol
  module RSpec
    module Matchers
      # Matcher that validates a response is a properly structured MCP tool response.
      #
      # @example Basic usage
      #   expect(response).to be_valid_mcp_tool_response
      #
      def be_valid_mcp_tool_response
        BeValidMcpToolResponse.new
      end

      class BeValidMcpToolResponse
        MCP_CONTENT_TYPES = %w[text image audio resource resource_link].freeze

        def initialize
          @failure_reasons = []
        end

        def matches?(actual)
          @actual = actual
          @failure_reasons = []
          @serialized = serialize_response(actual)

          return false if @serialized.nil?

          validate_structure &&
            validate_content &&
            validate_is_error_flag
        end

        def failure_message
          "expected #{@actual.class} to be a valid MCP tool response, but:\n" +
            @failure_reasons.map { |reason| "  - #{reason}" }.join("\n")
        end

        def failure_message_when_negated
          "expected #{@actual.class} not to be a valid MCP tool response, but it was"
        end

        def description
          "be a valid MCP tool response"
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

        def validate_structure
          unless @serialized.is_a?(Hash)
            @failure_reasons << "serialized response must be a Hash, got #{@serialized.class}"
            return false
          end

          has_content = @serialized.key?(:content) || @serialized.key?("content")
          has_structured = @serialized.key?(:structuredContent) || @serialized.key?("structuredContent")

          unless has_content || has_structured
            @failure_reasons << "response must have :content or :structuredContent key"
            return false
          end

          true
        end

        def validate_content
          content = @serialized[:content] || @serialized["content"]
          return true unless content

          unless content.is_a?(Array)
            @failure_reasons << "content must be an Array, got #{content.class}"
            return false
          end

          if content.empty?
            @failure_reasons << "content array must not be empty"
            return false
          end

          content.each_with_index do |item, index|
            validate_content_item(item, index)
          end

          @failure_reasons.empty?
        end

        def validate_content_item(item, index)
          unless item.is_a?(Hash)
            @failure_reasons << "content[#{index}] must be a Hash, got #{item.class}"
            return
          end

          type = item[:type] || item["type"]
          unless type
            @failure_reasons << "content[#{index}] must have a :type key"
            return
          end

          unless MCP_CONTENT_TYPES.include?(type)
            @failure_reasons << "content[#{index}] has invalid type '#{type}', must be one of: #{MCP_CONTENT_TYPES.join(", ")}"
          end
        end

        def validate_is_error_flag
          has_symbol_key = @serialized.key?(:isError)
          has_string_key = @serialized.key?("isError")

          unless has_symbol_key || has_string_key
            @failure_reasons << "response must have :isError key"
            return false
          end

          is_error = has_symbol_key ? @serialized[:isError] : @serialized["isError"]
          unless [true, false].include?(is_error)
            @failure_reasons << "isError must be a boolean, got #{is_error.class}"
            return false
          end

          true
        end
      end
    end
  end
end
