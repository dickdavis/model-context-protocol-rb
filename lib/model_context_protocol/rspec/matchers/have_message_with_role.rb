# frozen_string_literal: true

module ModelContextProtocol
  module RSpec
    module Matchers
      # Matcher that validates a prompt response contains a message with a specific role.
      #
      # @example Basic usage
      #   expect(response).to have_message_with_role("user")
      #
      # @example With content constraint
      #   expect(response).to have_message_with_role("assistant").containing("How can I help?")
      #
      # @example With regex content constraint
      #   expect(response).to have_message_with_role("user").containing(/generate.*excuses/i)
      #
      def have_message_with_role(role)
        HaveMessageWithRole.new(role)
      end

      class HaveMessageWithRole
        def initialize(role)
          @expected_role = role.to_s
          @expected_content = nil
          @failure_reasons = []
        end

        def containing(content)
          @expected_content = content
          self
        end

        def matches?(actual)
          @actual = actual
          @failure_reasons = []
          @serialized = serialize_response(actual)

          return false if @serialized.nil?

          validate_has_messages &&
            validate_has_role &&
            validate_content_match
        end

        def failure_message
          constraint = @expected_content ? " containing #{@expected_content.inspect}" : ""
          "expected response to have message with role '#{@expected_role}'#{constraint}, but:\n" +
            @failure_reasons.map { |reason| "  - #{reason}" }.join("\n")
        end

        def failure_message_when_negated
          constraint = @expected_content ? " containing #{@expected_content.inspect}" : ""
          "expected response not to have message with role '#{@expected_role}'#{constraint}, but it did"
        end

        def description
          constraint = @expected_content ? " containing #{@expected_content.inspect}" : ""
          "have message with role '#{@expected_role}'#{constraint}"
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

        def validate_has_messages
          @messages = @serialized[:messages] || @serialized["messages"]

          unless @messages
            @failure_reasons << "response does not have :messages key"
            return false
          end

          unless @messages.is_a?(Array)
            @failure_reasons << "messages must be an Array"
            return false
          end

          true
        end

        def validate_has_role
          @messages_with_role = @messages.select do |message|
            role = message[:role] || message["role"]
            role == @expected_role
          end

          if @messages_with_role.empty?
            actual_roles = @messages.map { |m| m[:role] || m["role"] }.uniq
            @failure_reasons << "no message with role '#{@expected_role}' found, found roles: #{actual_roles.inspect}"
            return false
          end

          true
        end

        def validate_content_match
          return true unless @expected_content

          matching_message = @messages_with_role.find do |message|
            content = message[:content] || message["content"]
            content_matches?(content)
          end

          unless matching_message
            @failure_reasons << "no '#{@expected_role}' message contains content matching #{@expected_content.inspect}"
            return false
          end

          true
        end

        def content_matches?(content)
          return false unless content

          # Content can be a hash with type/text or an array of content blocks
          texts = extract_texts(content)
          texts.any? { |text| text_matches?(text) }
        end

        def extract_texts(content)
          case content
          when Array
            content.flat_map { |item| extract_texts(item) }
          when Hash
            text = content[:text] || content["text"]
            text ? [text] : []
          else
            []
          end
        end

        def text_matches?(text)
          case @expected_content
          when Regexp
            @expected_content.match?(text)
          else
            text.to_s.include?(@expected_content.to_s)
          end
        end
      end
    end
  end
end
