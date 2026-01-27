# frozen_string_literal: true

module ModelContextProtocol
  module RSpec
    module Matchers
      # Matcher that validates a tool response contains audio content.
      #
      # @example Basic usage
      #   expect(response).to have_audio_content
      #
      # @example With mime type constraint
      #   expect(response).to have_audio_content(mime_type: "audio/mp3")
      #
      def have_audio_content(mime_type: nil)
        HaveAudioContent.new(mime_type: mime_type)
      end

      class HaveAudioContent
        def initialize(mime_type: nil)
          @expected_mime_type = mime_type
          @failure_reasons = []
        end

        def matches?(actual)
          @actual = actual
          @failure_reasons = []
          @serialized = serialize_response(actual)

          return false if @serialized.nil?

          validate_has_content &&
            validate_has_audio_content
        end

        def failure_message
          constraint = @expected_mime_type ? " with mime type '#{@expected_mime_type}'" : ""
          "expected response to have audio content#{constraint}, but:\n" +
            @failure_reasons.map { |reason| "  - #{reason}" }.join("\n")
        end

        def failure_message_when_negated
          constraint = @expected_mime_type ? " with mime type '#{@expected_mime_type}'" : ""
          "expected response not to have audio content#{constraint}, but it did"
        end

        def description
          constraint = @expected_mime_type ? " with mime type '#{@expected_mime_type}'" : ""
          "have audio content#{constraint}"
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

        def validate_has_audio_content
          audio_items = @content.select do |item|
            type = item[:type] || item["type"]
            type == "audio"
          end

          if audio_items.empty?
            @failure_reasons << "no audio content found in response"
            return false
          end

          if @expected_mime_type
            matching_item = audio_items.find do |item|
              mime_type = item[:mimeType] || item["mimeType"]
              mime_type == @expected_mime_type
            end

            unless matching_item
              actual_types = audio_items.map { |item| item[:mimeType] || item["mimeType"] }
              @failure_reasons << "no audio content with mime type '#{@expected_mime_type}' found, found: #{actual_types.inspect}"
              return false
            end
          end

          true
        end
      end
    end
  end
end
