# frozen_string_literal: true

module ModelContextProtocol
  module RSpec
    module Matchers
      # Matcher that validates a tool response contains resource link content.
      #
      # @example Basic usage
      #   expect(response).to have_resource_link_content
      #
      # @example With URI constraint
      #   expect(response).to have_resource_link_content(uri: "file:///path/to/file.txt")
      #
      # @example With name constraint
      #   expect(response).to have_resource_link_content(name: "my-resource")
      #
      # @example With both constraints
      #   expect(response).to have_resource_link_content(uri: "file:///path", name: "my-resource")
      #
      def have_resource_link_content(uri: nil, name: nil)
        HaveResourceLinkContent.new(uri: uri, name: name)
      end

      class HaveResourceLinkContent
        def initialize(uri: nil, name: nil)
          @expected_uri = uri
          @expected_name = name
          @failure_reasons = []
        end

        def matches?(actual)
          @actual = actual
          @failure_reasons = []
          @serialized = serialize_response(actual)

          return false if @serialized.nil?

          validate_has_content &&
            validate_has_resource_link_content
        end

        def failure_message
          constraints = build_constraint_message
          "expected response to have resource link content#{constraints}, but:\n" +
            @failure_reasons.map { |reason| "  - #{reason}" }.join("\n")
        end

        def failure_message_when_negated
          constraints = build_constraint_message
          "expected response not to have resource link content#{constraints}, but it did"
        end

        def description
          constraints = build_constraint_message
          "have resource link content#{constraints}"
        end

        private

        def build_constraint_message
          parts = []
          parts << "uri: '#{@expected_uri}'" if @expected_uri
          parts << "name: '#{@expected_name}'" if @expected_name
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

        def validate_has_resource_link_content
          resource_link_items = @content.select do |item|
            type = item[:type] || item["type"]
            type == "resource_link"
          end

          if resource_link_items.empty?
            @failure_reasons << "no resource link content found in response"
            return false
          end

          matching_items = resource_link_items.dup

          if @expected_uri
            matching_items = matching_items.select do |item|
              uri = item[:uri] || item["uri"]
              uri == @expected_uri
            end

            if matching_items.empty?
              actual_uris = resource_link_items.map { |item| item[:uri] || item["uri"] }
              @failure_reasons << "no resource link with uri '#{@expected_uri}' found, found: #{actual_uris.inspect}"
              return false
            end
          end

          if @expected_name
            matching_items = matching_items.select do |item|
              name = item[:name] || item["name"]
              name == @expected_name
            end

            if matching_items.empty?
              actual_names = resource_link_items.map { |item| item[:name] || item["name"] }
              @failure_reasons << "no resource link with name '#{@expected_name}' found, found: #{actual_names.inspect}"
              return false
            end
          end

          true
        end
      end
    end
  end
end
