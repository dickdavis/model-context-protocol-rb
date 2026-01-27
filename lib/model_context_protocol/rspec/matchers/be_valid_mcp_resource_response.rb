# frozen_string_literal: true

module ModelContextProtocol
  module RSpec
    module Matchers
      # Matcher that validates a response is a properly structured MCP resource response.
      #
      # @example Basic usage
      #   expect(response).to be_valid_mcp_resource_response
      #
      def be_valid_mcp_resource_response
        BeValidMcpResourceResponse.new
      end

      class BeValidMcpResourceResponse
        def initialize
          @failure_reasons = []
        end

        def matches?(actual)
          @actual = actual
          @failure_reasons = []
          @serialized = serialize_response(actual)

          return false if @serialized.nil?

          validate_structure &&
            validate_contents
        end

        def failure_message
          "expected #{@actual.class} to be a valid MCP resource response, but:\n" +
            @failure_reasons.map { |reason| "  - #{reason}" }.join("\n")
        end

        def failure_message_when_negated
          "expected #{@actual.class} not to be a valid MCP resource response, but it was"
        end

        def description
          "be a valid MCP resource response"
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

          has_contents = @serialized.key?(:contents) || @serialized.key?("contents")

          unless has_contents
            @failure_reasons << "response must have :contents key"
            return false
          end

          true
        end

        def validate_contents
          contents = @serialized[:contents] || @serialized["contents"]

          unless contents.is_a?(Array)
            @failure_reasons << "contents must be an Array, got #{contents.class}"
            return false
          end

          if contents.empty?
            @failure_reasons << "contents array must not be empty"
            return false
          end

          contents.each_with_index do |content, index|
            validate_content_item(content, index)
          end

          @failure_reasons.empty?
        end

        def validate_content_item(content, index)
          unless content.is_a?(Hash)
            @failure_reasons << "contents[#{index}] must be a Hash, got #{content.class}"
            return
          end

          uri = content[:uri] || content["uri"]
          unless uri
            @failure_reasons << "contents[#{index}] must have a :uri key"
            return
          end

          mime_type = content[:mimeType] || content["mimeType"]
          unless mime_type
            @failure_reasons << "contents[#{index}] must have a :mimeType key"
            return
          end

          has_text = content.key?(:text) || content.key?("text")
          has_blob = content.key?(:blob) || content.key?("blob")

          unless has_text || has_blob
            @failure_reasons << "contents[#{index}] must have either :text or :blob key"
          end
        end
      end
    end
  end
end
