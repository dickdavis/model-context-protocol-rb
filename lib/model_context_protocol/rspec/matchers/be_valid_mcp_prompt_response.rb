# frozen_string_literal: true

module ModelContextProtocol
  module RSpec
    module Matchers
      # Matcher that validates a response is a properly structured MCP prompt response.
      #
      # @example Basic usage
      #   expect(response).to be_valid_mcp_prompt_response
      #
      def be_valid_mcp_prompt_response
        BeValidMcpPromptResponse.new
      end

      class BeValidMcpPromptResponse
        VALID_ROLES = %w[user assistant].freeze

        def initialize
          @failure_reasons = []
        end

        def matches?(actual)
          @actual = actual
          @failure_reasons = []
          @serialized = serialize_response(actual)

          return false if @serialized.nil?

          validate_structure &&
            validate_messages
        end

        def failure_message
          "expected #{@actual.class} to be a valid MCP prompt response, but:\n" +
            @failure_reasons.map { |reason| "  - #{reason}" }.join("\n")
        end

        def failure_message_when_negated
          "expected #{@actual.class} not to be a valid MCP prompt response, but it was"
        end

        def description
          "be a valid MCP prompt response"
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

          has_messages = @serialized.key?(:messages) || @serialized.key?("messages")
          has_description = @serialized.key?(:description) || @serialized.key?("description")

          unless has_messages
            @failure_reasons << "response must have :messages key"
            return false
          end

          unless has_description
            @failure_reasons << "response must have :description key"
            return false
          end

          true
        end

        def validate_messages
          messages = @serialized[:messages] || @serialized["messages"]

          unless messages.is_a?(Array)
            @failure_reasons << "messages must be an Array, got #{messages.class}"
            return false
          end

          if messages.empty?
            @failure_reasons << "messages array must not be empty"
            return false
          end

          messages.each_with_index do |message, index|
            validate_message(message, index)
          end

          @failure_reasons.empty?
        end

        def validate_message(message, index)
          unless message.is_a?(Hash)
            @failure_reasons << "messages[#{index}] must be a Hash, got #{message.class}"
            return
          end

          role = message[:role] || message["role"]
          unless role
            @failure_reasons << "messages[#{index}] must have a :role key"
            return
          end

          unless VALID_ROLES.include?(role)
            @failure_reasons << "messages[#{index}] has invalid role '#{role}', must be one of: #{VALID_ROLES.join(", ")}"
            return
          end

          content = message[:content] || message["content"]
          unless content
            @failure_reasons << "messages[#{index}] must have a :content key"
          end
        end
      end
    end
  end
end
