require "spec_helper"
require "model_context_protocol/rspec"

RSpec.describe ModelContextProtocol::RSpec::Matchers::BeValidMcpClass do
  include ModelContextProtocol::RSpec::Matchers

  describe "#matches?" do
    context "with a valid Tool class" do
      it "matches without type constraint" do
        expect(TestToolWithTextResponse).to be_valid_mcp_class
      end

      it "matches with :tool type constraint" do
        expect(TestToolWithTextResponse).to be_valid_mcp_class(:tool)
      end

      it "fails with wrong type constraint" do
        expect(TestToolWithTextResponse).not_to be_valid_mcp_class(:prompt)
      end
    end

    context "with a valid Prompt class" do
      it "matches without type constraint" do
        expect(TestPrompt).to be_valid_mcp_class
      end

      it "matches with :prompt type constraint" do
        expect(TestPrompt).to be_valid_mcp_class(:prompt)
      end

      it "fails with wrong type constraint" do
        expect(TestPrompt).not_to be_valid_mcp_class(:tool)
      end
    end

    context "with a valid Resource class" do
      it "matches without type constraint" do
        expect(TestResource).to be_valid_mcp_class
      end

      it "matches with :resource type constraint" do
        expect(TestResource).to be_valid_mcp_class(:resource)
      end

      it "fails with wrong type constraint" do
        expect(TestResource).not_to be_valid_mcp_class(:tool)
      end
    end

    context "with a valid ResourceTemplate class" do
      it "matches without type constraint" do
        expect(TestResourceTemplate).to be_valid_mcp_class
      end

      it "matches with :resource_template type constraint" do
        expect(TestResourceTemplate).to be_valid_mcp_class(:resource_template)
      end

      it "fails with wrong type constraint" do
        expect(TestResourceTemplate).not_to be_valid_mcp_class(:resource)
      end
    end

    context "with an invalid class" do
      it "fails when class does not inherit from MCP base class" do
        expect(TestInvalidClass).not_to be_valid_mcp_class
      end
    end

    context "with a class missing required attributes" do
      let(:tool_without_name) do
        Class.new(ModelContextProtocol::Server::Tool) do
          define do
            description "A tool without a name"
            input_schema { {type: "object"} }
          end
        end
      end

      let(:tool_without_description) do
        Class.new(ModelContextProtocol::Server::Tool) do
          define do
            name "no_description_tool"
            input_schema { {type: "object"} }
          end
        end
      end

      it "fails when name is not defined" do
        expect(tool_without_name).not_to be_valid_mcp_class
      end

      it "fails when description is not defined" do
        expect(tool_without_description).not_to be_valid_mcp_class
      end
    end
  end

  describe "#failure_message" do
    it "provides helpful message when class does not inherit from MCP base" do
      matcher = be_valid_mcp_class
      matcher.matches?(TestInvalidClass)

      expect(matcher.failure_message).to include("does not inherit from any MCP base class")
    end

    it "provides helpful message when name is missing" do
      tool_without_name = Class.new(ModelContextProtocol::Server::Tool) do
        define do
          description "A tool"
          input_schema { {type: "object"} }
        end
      end

      matcher = be_valid_mcp_class
      matcher.matches?(tool_without_name)

      expect(matcher.failure_message).to include("name is not defined")
    end

    it "provides helpful message when type constraint fails" do
      matcher = be_valid_mcp_class(:prompt)
      matcher.matches?(TestToolWithTextResponse)

      expect(matcher.failure_message).to include("expected to inherit from")
      expect(matcher.failure_message).to include("Prompt")
    end

    it "includes the type constraint in the message" do
      matcher = be_valid_mcp_class(:tool)
      matcher.matches?(TestInvalidClass)

      expect(matcher.failure_message).to include("(tool)")
    end
  end

  describe "#description" do
    it "returns a description without type constraint" do
      matcher = be_valid_mcp_class
      expect(matcher.description).to eq("be a valid MCP class")
    end

    it "returns a description with type constraint" do
      matcher = be_valid_mcp_class(:tool)
      expect(matcher.description).to eq("be a valid MCP class (tool)")
    end
  end
end
