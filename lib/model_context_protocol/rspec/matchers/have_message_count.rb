# frozen_string_literal: true

module ModelContextProtocol
  module RSpec
    module Matchers
      # Matcher that validates a prompt response contains a specific number of messages.
      #
      # @example Basic usage
      #   expect(response).to have_message_count(3)
      #
      def have_message_count(expected_count)
        HaveMessageCount.new(expected_count)
      end

      class HaveMessageCount
        def initialize(expected_count)
          @expected_count = expected_count
          @failure_reasons = []
        end

        def matches?(actual)
          @actual = actual
          @failure_reasons = []
          @serialized = serialize_response(actual)

          return false if @serialized.nil?

          validate_has_messages &&
            validate_count
        end

        def failure_message
          "expected response to have #{@expected_count} message(s), but:\n" +
            @failure_reasons.map { |reason| "  - #{reason}" }.join("\n")
        end

        def failure_message_when_negated
          "expected response not to have #{@expected_count} message(s), but it did"
        end

        def description
          "have #{@expected_count} message(s)"
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

        def validate_count
          actual_count = @messages.size

          if actual_count != @expected_count
            @failure_reasons << "expected #{@expected_count} message(s), got #{actual_count}"
            return false
          end

          true
        end
      end
    end
  end
end
