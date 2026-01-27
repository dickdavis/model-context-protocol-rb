# frozen_string_literal: true

module ModelContextProtocol
  module RSpec
    module Matchers
      # Matcher that validates a resource response contains binary blob content.
      #
      # @example Basic usage
      #   expect(response).to have_resource_blob
      #
      # @example With base64 content match
      #   expect(response).to have_resource_blob("dGVzdA==")
      #
      def have_resource_blob(expected_blob = nil)
        HaveResourceBlob.new(expected_blob)
      end

      class HaveResourceBlob
        def initialize(expected_blob = nil)
          @expected_blob = expected_blob
          @failure_reasons = []
        end

        def matches?(actual)
          @actual = actual
          @failure_reasons = []
          @serialized = serialize_response(actual)

          return false if @serialized.nil?

          validate_has_contents &&
            validate_has_blob
        end

        def failure_message
          constraint = @expected_blob ? " matching #{@expected_blob.inspect}" : ""
          "expected resource response to have blob content#{constraint}, but:\n" +
            @failure_reasons.map { |reason| "  - #{reason}" }.join("\n")
        end

        def failure_message_when_negated
          constraint = @expected_blob ? " matching #{@expected_blob.inspect}" : ""
          "expected resource response not to have blob content#{constraint}, but it did"
        end

        def description
          constraint = @expected_blob ? " matching #{@expected_blob.inspect}" : ""
          "have resource blob content#{constraint}"
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

        def validate_has_blob
          blob_items = @contents.select do |content|
            content.key?(:blob) || content.key?("blob")
          end

          if blob_items.empty?
            @failure_reasons << "no blob content found in resource response"
            return false
          end

          if @expected_blob
            matching_item = blob_items.find do |content|
              blob = content[:blob] || content["blob"]
              blob == @expected_blob
            end

            unless matching_item
              actual_blobs = blob_items.map { |c| c[:blob] || c["blob"] }
              @failure_reasons << "no blob content matched #{@expected_blob.inspect}, found: #{actual_blobs.inspect}"
              return false
            end
          end

          true
        end
      end
    end
  end
end
