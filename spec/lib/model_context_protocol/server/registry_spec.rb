require "spec_helper"

RSpec.describe ModelContextProtocol::Server::Registry do
  describe "#new" do
    it "initializes with an empty registry when no block is provided" do
      registry = described_class.new

      expect(registry.instance_variable_get(:@prompts)).to be_empty
      expect(registry.instance_variable_get(:@resources)).to be_empty
      expect(registry.instance_variable_get(:@resource_templates)).to be_empty
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
      expect(prompts.first[:name]).to eq("brainstorm_excuses")
      expect(prompts.first[:description]).to eq("A prompt for brainstorming excuses to get out of something")
      expect(prompts.first[:arguments]).to be_an(Array)
    end

    it "registers a resource class" do
      registry.register(TestResource)
      resources = registry.instance_variable_get(:@resources)

      aggregate_failures do
        expect(resources.size).to eq(1)
        expect(resources.first[:klass]).to eq(TestResource)
        expect(resources.first[:name]).to eq("top-secret-plans.txt")
        expect(resources.first[:uri]).to eq("file:///top-secret-plans.txt")
        expect(resources.first[:description]).to eq("Top secret plans to do top secret things")
        expect(resources.first[:mimeType]).to eq("text/plain")
      end
    end

    it "registers a resource template class" do
      registry.register(TestResourceTemplate)
      resource_templates = registry.instance_variable_get(:@resource_templates)

      expect(resource_templates.size).to eq(1)
      expect(resource_templates.first[:klass]).to eq(TestResourceTemplate)
      expect(resource_templates.first[:name]).to eq("project-document-resource-template")
      expect(resource_templates.first[:uriTemplate]).to eq("file:///{name}")
      expect(resource_templates.first[:description]).to eq("A resource template for retrieving project documents")
      expect(resource_templates.first[:mimeType]).to eq("text/plain")
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

        resource_templates do
          register TestResourceTemplate
        end

        tools list_changed: true do
          register TestToolWithTextResponse
        end
      end

      expect(registry.instance_variable_get(:@prompts).size).to eq(1)
      expect(registry.instance_variable_get(:@resources).size).to eq(1)
      expect(registry.instance_variable_get(:@resource_templates).size).to eq(1)
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

        resource_templates do
          register TestResourceTemplate
        end

        tools do
          register TestToolWithTextResponse
        end
      end
    end

    describe "#find_prompt" do
      it "returns the prompt class when found" do
        expect(registry.find_prompt("brainstorm_excuses")).to eq(TestPrompt)
      end

      it "returns nil when the prompt is not found" do
        expect(registry.find_prompt("nonexistent_prompt")).to be_nil
      end
    end

    describe "#find_resource" do
      it "returns the resource class when found" do
        expect(registry.find_resource("file:///top-secret-plans.txt")).to eq(TestResource)
      end

      it "returns nil when the resource is not found" do
        expect(registry.find_resource("resource://nonexistent")).to be_nil
      end
    end

    describe "#find_resource_template" do
      it "returns the resource template class when a matching URI is found" do
        uri = "file:///{name}"
        expect(registry.find_resource_template(uri)).to eq(TestResourceTemplate)
      end

      it "returns nil when no matching template is found" do
        uri = "invalid://test-name"
        expect(registry.find_resource_template(uri)).to be_nil
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

        resource_templates do
          register TestResourceTemplate
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
            name: "brainstorm_excuses",
            description: "A prompt for brainstorming excuses to get out of something"
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
            name: "top-secret-plans.txt",
            uri: "file:///top-secret-plans.txt",
            description: "Top secret plans to do top secret things",
            mimeType: "text/plain"
          )
          expect(result.resources.first).not_to have_key(:klass)
        end
      end
    end

    describe "#resource_templates_data" do
      it "returns a hash with resource templates array without klass references" do
        result = registry.resource_templates_data

        aggregate_failures do
          expect(result).to be_a(ModelContextProtocol::Server::Registry::ResourceTemplatesData)
          expect(result.resource_templates).to be_an(Array)
          expect(result.resource_templates.first).to include(
            name: "project-document-resource-template",
            uriTemplate: "file:///{name}",
            description: "A resource template for retrieving project documents",
            mimeType: "text/plain"
          )
          expect(result.resource_templates.first).not_to have_key(:klass)
        end
      end

      it "serializes resource templates data properly" do
        result = registry.resource_templates_data.serialized

        expect(result).to eq(
          resourceTemplates: [
            {
              name: "project-document-resource-template",
              uriTemplate: "file:///{name}",
              description: "A resource template for retrieving project documents",
              mimeType: "text/plain"
            }
          ]
        )
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

  describe "pagination support" do
    let(:large_registry) do
      described_class.new do
        prompts do
          15.times do |i|
            prompt_class = Class.new(ModelContextProtocol::Server::Prompt) do
              define_method(:call) do |args, logger, context|
                ModelContextProtocol::Server::GetPromptResponse[
                  description: "Test prompt #{i}",
                  messages: [
                    {
                      role: "user",
                      content: {
                        type: "text",
                        text: "Test prompt #{i} content"
                      }
                    }
                  ]
                ]
              end
            end
            prompt_class.define_singleton_method(:definition) do
              {
                name: "prompt_#{i}",
                description: "Test prompt #{i}",
                arguments: [{name: "input", description: "Input parameter"}]
              }
            end
            register prompt_class
          end
        end

        resources do
          12.times do |i|
            resource_class = Class.new(ModelContextProtocol::Server::Resource) do
              define_method(:call) do |logger, context|
                ModelContextProtocol::Server::ReadResourceResponse[
                  contents: [
                    {
                      uri: "file:///resource_#{i}.txt",
                      mimeType: "text/plain",
                      text: "Content #{i}"
                    }
                  ]
                ]
              end
            end
            resource_class.define_singleton_method(:definition) do
              {
                name: "resource_#{i}",
                description: "Test resource #{i}",
                uri: "file:///resource_#{i}.txt",
                mimeType: "text/plain"
              }
            end
            register resource_class
          end
        end

        resource_templates do
          8.times do |i|
            template_class = Class.new(ModelContextProtocol::Server::ResourceTemplate)
            template_class.define_singleton_method(:definition) do
              {
                name: "template_#{i}",
                description: "Test template #{i}",
                uriTemplate: "file:///templates/{name}_#{i}",
                mimeType: "text/plain"
              }
            end
            register template_class
          end
        end

        tools do
          20.times do |i|
            tool_class = Class.new(ModelContextProtocol::Server::Tool) do
              define_method(:call) do |args, logger, context|
                ModelContextProtocol::Server::CallToolResponse[
                  content: [
                    {
                      type: "text",
                      text: "Tool #{i} executed"
                    }
                  ]
                ]
              end
            end
            tool_class.define_singleton_method(:definition) do
              {
                name: "tool_#{i}",
                description: "Test tool #{i}",
                inputSchema: {
                  type: "object",
                  properties: {
                    input: {type: "string"}
                  }
                }
              }
            end
            register tool_class
          end
        end
      end
    end

    describe "#prompts_data with pagination" do
      it "returns all prompts without pagination parameters" do
        result = large_registry.prompts_data

        aggregate_failures do
          expect(result.prompts.length).to eq(15)
          expect(result.next_cursor).to be_nil
          expect(result.serialized).not_to have_key(:nextCursor)
        end
      end

      it "returns first page when page_size is provided" do
        result = large_registry.prompts_data(page_size: 5)

        aggregate_failures do
          expect(result.prompts.length).to eq(5)
          expect(result.prompts.first[:name]).to eq("prompt_0")
          expect(result.prompts.last[:name]).to eq("prompt_4")
          expect(result.next_cursor).not_to be_nil
          expect(result.serialized[:nextCursor]).not_to be_nil
        end
      end

      it "returns subsequent page with cursor" do
        first_page = large_registry.prompts_data(page_size: 5)
        second_page = large_registry.prompts_data(
          cursor: first_page.next_cursor,
          page_size: 5
        )

        aggregate_failures do
          expect(second_page.prompts.length).to eq(5)
          expect(second_page.prompts.first[:name]).to eq("prompt_5")
          expect(second_page.prompts.last[:name]).to eq("prompt_9")
          expect(second_page.next_cursor).not_to be_nil
        end
      end

      it "returns last page with no cursor" do
        first_page = large_registry.prompts_data(page_size: 5)
        second_page = large_registry.prompts_data(
          cursor: first_page.next_cursor,
          page_size: 5
        )
        last_page = large_registry.prompts_data(
          cursor: second_page.next_cursor,
          page_size: 5
        )

        aggregate_failures do
          expect(last_page.prompts.length).to eq(5)
          expect(last_page.prompts.first[:name]).to eq("prompt_10")
          expect(last_page.prompts.last[:name]).to eq("prompt_14")
          expect(last_page.next_cursor).to be_nil
          expect(last_page.serialized).not_to have_key(:nextCursor)
        end
      end

      it "applies cursor TTL when provided" do
        result = large_registry.prompts_data(page_size: 5, cursor_ttl: 1800)
        cursor_data = JSON.parse(Base64.urlsafe_decode64(result.next_cursor))

        aggregate_failures do
          expect(result.next_cursor).not_to be_nil
          expect(cursor_data["expires_at"]).to be > Time.now.to_i
        end
      end

      it "excludes klass from paginated results" do
        result = large_registry.prompts_data(page_size: 3)

        result.prompts.each do |prompt|
          aggregate_failures do
            expect(prompt).not_to have_key(:klass)
            expect(prompt).to have_key(:name)
            expect(prompt).to have_key(:description)
          end
        end
      end
    end

    describe "#resources_data with pagination" do
      it "returns all resources without pagination parameters" do
        result = large_registry.resources_data

        aggregate_failures do
          expect(result.resources.length).to eq(12)
          expect(result.next_cursor).to be_nil
        end
      end

      it "paginates resources correctly" do
        result = large_registry.resources_data(page_size: 4)

        aggregate_failures do
          expect(result.resources.length).to eq(4)
          expect(result.resources.first[:name]).to eq("resource_0")
          expect(result.resources.last[:name]).to eq("resource_3")
          expect(result.next_cursor).not_to be_nil
        end
      end

      it "handles last page correctly" do
        page1 = large_registry.resources_data(page_size: 4)
        page2 = large_registry.resources_data(cursor: page1.next_cursor, page_size: 4)
        page3 = large_registry.resources_data(cursor: page2.next_cursor, page_size: 4)

        aggregate_failures do
          expect(page3.resources.length).to eq(4)
          expect(page3.resources.first[:name]).to eq("resource_8")
          expect(page3.resources.last[:name]).to eq("resource_11")
          expect(page3.next_cursor).to be_nil
        end
      end

      it "serializes paginated resources correctly" do
        result = large_registry.resources_data(page_size: 3)
        serialized = result.serialized

        aggregate_failures do
          expect(serialized[:resources].length).to eq(3)
          expect(serialized[:nextCursor]).to be_a(String)
          expect(serialized[:resources].first).to include(:name, :uri, :description, :mimeType)
          expect(serialized[:resources].first).not_to have_key(:klass)
        end
      end
    end

    describe "#resource_templates_data with pagination" do
      it "returns all templates without pagination parameters" do
        result = large_registry.resource_templates_data

        aggregate_failures do
          expect(result.resource_templates.length).to eq(8)
          expect(result.next_cursor).to be_nil
        end
      end

      it "paginates resource templates correctly" do
        result = large_registry.resource_templates_data(page_size: 3)

        aggregate_failures do
          expect(result.resource_templates.length).to eq(3)
          expect(result.resource_templates.first[:name]).to eq("template_0")
          expect(result.resource_templates.last[:name]).to eq("template_2")
          expect(result.next_cursor).not_to be_nil
        end
      end

      it "handles multiple pages correctly" do
        page1 = large_registry.resource_templates_data(page_size: 3)
        page2 = large_registry.resource_templates_data(
          cursor: page1.next_cursor,
          page_size: 3
        )

        aggregate_failures do
          expect(page2.resource_templates.length).to eq(3)
          expect(page2.resource_templates.first[:name]).to eq("template_3")
          expect(page2.resource_templates.last[:name]).to eq("template_5")
          expect(page2.next_cursor).not_to be_nil
        end
      end

      it "excludes completions and klass from results" do
        result = large_registry.resource_templates_data(page_size: 2)

        result.resource_templates.each do |template|
          aggregate_failures do
            expect(template).not_to have_key(:klass)
            expect(template).not_to have_key(:completions)
            expect(template).to have_key(:name)
            expect(template).to have_key(:uriTemplate)
          end
        end
      end
    end

    describe "#tools_data with pagination" do
      it "returns all tools without pagination parameters" do
        result = large_registry.tools_data

        aggregate_failures do
          expect(result.tools.length).to eq(20)
          expect(result.next_cursor).to be_nil
        end
      end

      it "paginates tools correctly" do
        result = large_registry.tools_data(page_size: 6)

        aggregate_failures do
          expect(result.tools.length).to eq(6)
          expect(result.tools.first[:name]).to eq("tool_0")
          expect(result.tools.last[:name]).to eq("tool_5")
          expect(result.next_cursor).not_to be_nil
        end
      end

      it "handles remainder pages correctly" do
        page1 = large_registry.tools_data(page_size: 6)
        page2 = large_registry.tools_data(cursor: page1.next_cursor, page_size: 6)
        page3 = large_registry.tools_data(cursor: page2.next_cursor, page_size: 6)
        page4 = large_registry.tools_data(cursor: page3.next_cursor, page_size: 6)

        aggregate_failures do
          expect(page1.tools.length).to eq(6)
          expect(page2.tools.length).to eq(6)
          expect(page3.tools.length).to eq(6)
          expect(page4.tools.length).to eq(2)
          expect(page4.tools.first[:name]).to eq("tool_18")
          expect(page4.tools.last[:name]).to eq("tool_19")
          expect(page4.next_cursor).to be_nil
        end
      end

      it "serializes with proper nextCursor format" do
        result = large_registry.tools_data(page_size: 5)
        serialized = result.serialized

        aggregate_failures do
          expect(serialized).to have_key(:tools)
          expect(serialized).to have_key(:nextCursor)
          expect(serialized[:tools]).to be_an(Array)
          expect(serialized[:nextCursor]).to be_a(String)
          expect(serialized[:nextCursor]).not_to be_empty
        end
      end
    end

    describe "cursor edge cases" do
      it "handles invalid cursors gracefully" do
        expect {
          large_registry.prompts_data(cursor: "invalid_cursor")
        }.to raise_error(ModelContextProtocol::Server::Pagination::InvalidCursorError)
      end

      it "handles cursor pointing beyond collection" do
        fake_cursor = ModelContextProtocol::Server::Pagination.encode_cursor(999, 1000)
        result = large_registry.prompts_data(cursor: fake_cursor, page_size: 5)

        aggregate_failures do
          expect(result.prompts).to be_empty
          expect(result.next_cursor).to be_nil
        end
      end

      it "respects page size limits" do
        result = large_registry.prompts_data(page_size: 100)

        aggregate_failures do
          expect(result.prompts.length).to eq(15) # All items
          expect(result.next_cursor).to be_nil
        end
      end
    end

    describe "mixed pagination parameters" do
      it "processes cursor with custom page_size" do
        first_page = large_registry.tools_data(page_size: 3)
        second_page = large_registry.tools_data(
          cursor: first_page.next_cursor,
          page_size: 5
        )

        aggregate_failures do
          expect(first_page.tools.length).to eq(3)
          expect(second_page.tools.length).to eq(5)
          expect(second_page.tools.first[:name]).to eq("tool_3")
          expect(second_page.tools.last[:name]).to eq("tool_7")
        end
      end

      it "uses provided cursor_ttl parameter" do
        custom_ttl = 7200
        result = large_registry.resources_data(page_size: 4, cursor_ttl: custom_ttl)
        cursor_data = JSON.parse(Base64.urlsafe_decode64(result.next_cursor))
        expected_expiry = Time.now.to_i + custom_ttl

        expect(cursor_data["expires_at"]).to be_within(5).of(expected_expiry)
      end

      it "handles nil cursor_ttl (no expiration)" do
        result = large_registry.prompts_data(page_size: 3, cursor_ttl: nil)
        cursor_data = JSON.parse(Base64.urlsafe_decode64(result.next_cursor))

        expect(cursor_data).not_to have_key("expires_at")
      end
    end
  end
end
