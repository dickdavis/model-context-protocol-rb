# frozen_string_literal: true

module ModelContextProtocol
  module RSpec
    module Matchers
      # Matcher that validates a tool response contains embedded resource content.
      #
      # @example Basic usage
      #   expect(response).to have_embedded_resource_content
      #
      # @example With URI constraint
      #   expect(response).to have_embedded_resource_content(uri: "file:///path/to/file.txt")
      #
      def have_embedded_resource_content(uri: nil, mime_type: nil)
        HaveEmbeddedResourceContent.new(uri: uri, mime_type: mime_type)
      end

      class HaveEmbeddedResourceContent
        def initialize(uri: nil, mime_type: nil)
          @expected_uri = uri
          @expected_mime_type = mime_type
          @failure_reasons = []
        end

        def matches?(actual)
          @actual = actual
          @failure_reasons = []
          @serialized = serialize_response(actual)

          return false if @serialized.nil?

          validate_has_content &&
            validate_has_embedded_resource_content
        end

        def failure_message
          constraints = build_constraint_message
          "expected response to have embedded resource content#{constraints}, but:\n" +
            @failure_reasons.map { |reason| "  - #{reason}" }.join("\n")
        end

        def failure_message_when_negated
          constraints = build_constraint_message
          "expected response not to have embedded resource content#{constraints}, but it did"
        end

        def description
          constraints = build_constraint_message
          "have embedded resource content#{constraints}"
        end

        private

        def build_constraint_message
          parts = []
          parts << "uri: '#{@expected_uri}'" if @expected_uri
          parts << "mime_type: '#{@expected_mime_type}'" if @expected_mime_type
          parts.empty? ? "" : " with #{parts.join(", ")}"
        end

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

        def validate_has_embedded_resource_content
          resource_items = @content.select do |item|
            type = item[:type] || item["type"]
            type == "resource"
          end

          if resource_items.empty?
            @failure_reasons << "no embedded resource content found in response"
            return false
          end

          matching_items = resource_items.dup

          if @expected_uri
            matching_items = matching_items.select do |item|
              resource = item[:resource] || item["resource"] || {}
              # Resource can be directly embedded (uri at top level) or have contents array
              uri = resource[:uri] || resource["uri"]
              if uri
                uri == @expected_uri
              else
                contents = resource[:contents] || resource["contents"] || []
                contents.any? do |content|
                  content_uri = content[:uri] || content["uri"]
                  content_uri == @expected_uri
                end
              end
            end

            if matching_items.empty?
              @failure_reasons << "no embedded resource with uri '#{@expected_uri}' found"
              return false
            end
          end

          if @expected_mime_type
            matching_items = matching_items.select do |item|
              resource = item[:resource] || item["resource"] || {}
              # Resource can be directly embedded (mimeType at top level) or have contents array
              mime_type = resource[:mimeType] || resource["mimeType"]
              if mime_type
                mime_type == @expected_mime_type
              else
                contents = resource[:contents] || resource["contents"] || []
                contents.any? do |content|
                  content_mime_type = content[:mimeType] || content["mimeType"]
                  content_mime_type == @expected_mime_type
                end
              end
            end

            if matching_items.empty?
              @failure_reasons << "no embedded resource with mime type '#{@expected_mime_type}' found"
              return false
            end
          end

          true
        end
      end
    end
  end
end
