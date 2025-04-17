require "spec_helper"

RSpec.describe ModelContextProtocol::Server::Registry do
  describe "#new" do
    it "initializes with an empty registry when no block is provided" do
      registry = described_class.new

      expect(registry.instance_variable_get(:@prompts)).to be_empty
      expect(registry.instance_variable_get(:@resources)).to be_empty
      expect(registry.instance_variable_get(:@tools)).to be_empty
    end

    it "evaluates the block in the context of the registry" do
      registry = described_class.new do
        prompts list_changed: true
        resources list_changed: true, subscribe: true
        tools list_changed: true
      end

      expect(registry.prompts_options).to eq(list_changed: true)
      expect(registry.resources_options).to eq(list_changed: true, subscribe: true)
      expect(registry.tools_options).to eq(list_changed: true)
    end
  end

  describe "#register" do
    let(:registry) { described_class.new }

    it "registers a prompt class" do
      registry.register(TestPrompt)
      prompts = registry.instance_variable_get(:@prompts)

      expect(prompts.size).to eq(1)
      expect(prompts.first[:klass]).to eq(TestPrompt)
      expect(prompts.first[:name]).to eq("Test Prompt")
      expect(prompts.first[:description]).to eq("A test prompt")
      expect(prompts.first[:arguments]).to be_an(Array)
    end

    it "registers a resource class" do
      registry.register(TestResource)
      resources = registry.instance_variable_get(:@resources)

      expect(resources.size).to eq(1)
      expect(resources.first[:klass]).to eq(TestResource)
      expect(resources.first[:name]).to eq("Test Resource")
      expect(resources.first[:uri]).to eq("resource://test-resource")
      expect(resources.first[:description]).to eq("A test resource")
      expect(resources.first[:mimeType]).to eq("text/plain")
    end

    it "registers a tool class" do
      registry.register(TestToolWithTextResponse)
      tools = registry.instance_variable_get(:@tools)

      aggregate_failures do
        expect(tools.size).to eq(1)
        expect(tools.first[:klass]).to eq(TestToolWithTextResponse)
        expect(tools.first[:name]).to eq("double")
        expect(tools.first[:description]).to eq("Doubles the provided number")
        expect(tools.first[:inputSchema]).to be_a(Hash)
      end
    end

    it "raises an error for invalid class types" do
      expect { registry.register(TestInvalidClass) }.to raise_error(ArgumentError, "Unknown class type: TestInvalidClass")
    end
  end

  describe "DSL methods" do
    it "registers classes within the DSL blocks" do
      registry = described_class.new do
        prompts list_changed: true do
          register TestPrompt
        end

        resources list_changed: true, subscribe: true do
          register TestResource
        end

        tools list_changed: true do
          register TestToolWithTextResponse
        end
      end

      expect(registry.instance_variable_get(:@prompts).size).to eq(1)
      expect(registry.instance_variable_get(:@resources).size).to eq(1)
      expect(registry.instance_variable_get(:@tools).size).to eq(1)
      expect(registry.prompts_options).to eq(list_changed: true)
      expect(registry.resources_options).to eq(list_changed: true, subscribe: true)
      expect(registry.tools_options).to eq(list_changed: true)
    end
  end

  describe "finder methods" do
    let(:registry) do
      described_class.new do
        prompts do
          register TestPrompt
        end

        resources do
          register TestResource
        end

        tools do
          register TestToolWithTextResponse
        end
      end
    end

    describe "#find_prompt" do
      it "returns the prompt class when found" do
        expect(registry.find_prompt("Test Prompt")).to eq(TestPrompt)
      end

      it "returns nil when the prompt is not found" do
        expect(registry.find_prompt("nonexistent_prompt")).to be_nil
      end
    end

    describe "#find_resource" do
      it "returns the resource class when found" do
        expect(registry.find_resource("resource://test-resource")).to eq(TestResource)
      end

      it "returns nil when the resource is not found" do
        expect(registry.find_resource("resource://nonexistent")).to be_nil
      end
    end

    describe "#find_tool" do
      it "returns the tool class when found" do
        expect(registry.find_tool("double")).to eq(TestToolWithTextResponse)
      end

      it "returns nil when the tool is not found" do
        expect(registry.find_tool("nonexistent_tool")).to be_nil
      end
    end
  end

  describe "serialization methods" do
    let(:registry) do
      described_class.new do
        prompts do
          register TestPrompt
        end

        resources do
          register TestResource
        end

        tools do
          register TestToolWithTextResponse
        end
      end
    end

    describe "#prompts_data" do
      it "returns a hash with prompts array without klass references" do
        result = registry.prompts_data

        aggregate_failures do
          expect(result).to be_a(ModelContextProtocol::Server::Registry::PromptsData)
          expect(result.prompts).to be_an(Array)
          expect(result.prompts.first).to include(
            name: "Test Prompt",
            description: "A test prompt"
          )
          expect(result.prompts.first).not_to have_key(:klass)
        end
      end
    end

    describe "#resources_data" do
      it "returns a hash with resources array without klass references" do
        result = registry.resources_data

        aggregate_failures do
          expect(result).to be_a(ModelContextProtocol::Server::Registry::ResourcesData)
          expect(result.resources).to be_an(Array)
          expect(result.resources.first).to include(
            name: "Test Resource",
            uri: "resource://test-resource",
            description: "A test resource",
            mimeType: "text/plain"
          )
          expect(result.resources.first).not_to have_key(:klass)
        end
      end
    end

    describe "#tools_data" do
      it "returns a hash with tools array without klass references" do
        result = registry.tools_data

        aggregate_failures do
          expect(result).to be_a(ModelContextProtocol::Server::Registry::ToolsData)
          expect(result.tools).to be_an(Array)
          expect(result.tools.first).to include(
            name: "double",
            description: "Doubles the provided number"
          )
          expect(result.tools.first).to have_key(:inputSchema)
          expect(result.tools.first).not_to have_key(:klass)
        end
      end
    end
  end
end
