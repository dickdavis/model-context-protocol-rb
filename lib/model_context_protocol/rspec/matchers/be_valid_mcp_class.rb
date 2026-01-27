# frozen_string_literal: true

module ModelContextProtocol
  module RSpec
    module Matchers
      # Matcher that validates a class is a properly defined MCP class.
      #
      # @example Basic usage
      #   expect(MyTool).to be_valid_mcp_class
      #
      # @example With type constraint
      #   expect(MyTool).to be_valid_mcp_class(:tool)
      #   expect(MyPrompt).to be_valid_mcp_class(:prompt)
      #   expect(MyResource).to be_valid_mcp_class(:resource)
      #   expect(MyTemplate).to be_valid_mcp_class(:resource_template)
      #
      def be_valid_mcp_class(expected_type = nil)
        BeValidMcpClass.new(expected_type)
      end

      class BeValidMcpClass
        BASE_CLASSES = {
          tool: ModelContextProtocol::Server::Tool,
          prompt: ModelContextProtocol::Server::Prompt,
          resource: ModelContextProtocol::Server::Resource,
          resource_template: ModelContextProtocol::Server::ResourceTemplate
        }.freeze

        def initialize(expected_type)
          @expected_type = expected_type
          @failure_reasons = []
        end

        def matches?(actual)
          @actual = actual
          @failure_reasons = []

          validate_inheritance &&
            validate_name_defined &&
            validate_description_defined
        end

        def failure_message
          "expected #{@actual} to be a valid MCP class#{type_constraint_message}, but:\n" +
            @failure_reasons.map { |reason| "  - #{reason}" }.join("\n")
        end

        def failure_message_when_negated
          "expected #{@actual} not to be a valid MCP class#{type_constraint_message}, but it was"
        end

        def description
          "be a valid MCP class#{type_constraint_message}"
        end

        private

        def type_constraint_message
          @expected_type ? " (#{@expected_type})" : ""
        end

        def validate_inheritance
          if @expected_type
            expected_base = BASE_CLASSES[@expected_type]
            unless expected_base
              @failure_reasons << "unknown type :#{@expected_type}. Valid types: #{BASE_CLASSES.keys.join(", ")}"
              return false
            end

            unless @actual < expected_base
              @failure_reasons << "expected to inherit from #{expected_base}, but doesn't"
              return false
            end
          else
            unless BASE_CLASSES.values.any? { |base| @actual < base }
              @failure_reasons << "does not inherit from any MCP base class (Tool, Prompt, Resource, or ResourceTemplate)"
              return false
            end
          end
          true
        end

        def validate_name_defined
          if @actual.respond_to?(:name) && !@actual.name.nil? && !@actual.name.to_s.empty?
            true
          else
            @failure_reasons << "name is not defined"
            false
          end
        end

        def validate_description_defined
          if @actual.respond_to?(:description) && !@actual.description.nil? && !@actual.description.to_s.empty?
            true
          else
            @failure_reasons << "description is not defined"
            false
          end
        end
      end
    end
  end
end
