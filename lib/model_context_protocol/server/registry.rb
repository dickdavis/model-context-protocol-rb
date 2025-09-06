module ModelContextProtocol
  class Server::Registry
    attr_reader :prompts_options, :resources_options, :tools_options

    def self.new(&block)
      registry = allocate
      registry.send(:initialize)
      registry.instance_eval(&block) if block
      registry
    end

    def initialize
      @prompts = []
      @resources = []
      @resource_templates = []
      @tools = []
      @prompts_options = {}
      @resources_options = {}
      @tools_options = {}
    end

    def prompts(options = {}, &block)
      @prompts_options = options
      instance_eval(&block) if block
    end

    def resources(options = {}, &block)
      @resources_options = options
      instance_eval(&block) if block
    end

    def resource_templates(&block)
      instance_eval(&block) if block
    end

    def tools(options = {}, &block)
      @tools_options = options
      instance_eval(&block) if block
    end

    def register(klass)
      definition = klass.definition
      entry = {klass: klass}.merge(definition)

      case klass.ancestors
      when ->(ancestors) { ancestors.include?(ModelContextProtocol::Server::Prompt) }
        @prompts << entry
      when ->(ancestors) { ancestors.include?(ModelContextProtocol::Server::Resource) }
        @resources << entry
      when ->(ancestors) { ancestors.include?(ModelContextProtocol::Server::ResourceTemplate) }
        @resource_templates << entry
      when ->(ancestors) { ancestors.include?(ModelContextProtocol::Server::Tool) }
        @tools << entry
      else
        raise ArgumentError, "Unknown class type: #{klass}"
      end
    end

    def find_prompt(name)
      find_by_name(@prompts, name)
    end

    def find_resource(uri)
      entry = @resources.find { |r| r[:uri] == uri }
      entry ? entry[:klass] : nil
    end

    def find_resource_template(uri)
      entry = @resource_templates.find { |r| uri == r[:uriTemplate] }
      entry ? entry[:klass] : nil
    end

    def find_tool(name)
      find_by_name(@tools, name)
    end

    def prompts_data(cursor: nil, page_size: nil, cursor_ttl: nil)
      items = @prompts.map { |entry| entry.except(:klass) }

      if cursor || page_size
        paginated = Server::Pagination.paginate(
          items,
          cursor: cursor,
          page_size: page_size || 100,
          cursor_ttl: cursor_ttl
        )

        PromptsData[prompts: paginated.items, next_cursor: paginated.next_cursor]
      else
        PromptsData[prompts: items]
      end
    end

    def resources_data(cursor: nil, page_size: nil, cursor_ttl: nil)
      items = @resources.map { |entry| entry.except(:klass) }

      if cursor || page_size
        paginated = Server::Pagination.paginate(
          items,
          cursor: cursor,
          page_size: page_size || 100,
          cursor_ttl: cursor_ttl
        )

        ResourcesData[resources: paginated.items, next_cursor: paginated.next_cursor]
      else
        ResourcesData[resources: items]
      end
    end

    def resource_templates_data(cursor: nil, page_size: nil, cursor_ttl: nil)
      items = @resource_templates.map { |entry| entry.except(:klass, :completions) }

      if cursor || page_size
        paginated = Server::Pagination.paginate(
          items,
          cursor: cursor,
          page_size: page_size || 100,
          cursor_ttl: cursor_ttl
        )

        ResourceTemplatesData[resource_templates: paginated.items, next_cursor: paginated.next_cursor]
      else
        ResourceTemplatesData[resource_templates: items]
      end
    end

    def tools_data(cursor: nil, page_size: nil, cursor_ttl: nil)
      items = @tools.map { |entry| entry.except(:klass) }

      if cursor || page_size
        paginated = Server::Pagination.paginate(
          items,
          cursor: cursor,
          page_size: page_size || 100,
          cursor_ttl: cursor_ttl
        )

        ToolsData[tools: paginated.items, next_cursor: paginated.next_cursor]
      else
        ToolsData[tools: items]
      end
    end

    private

    PromptsData = Data.define(:prompts, :next_cursor) do
      def initialize(prompts:, next_cursor: nil)
        super
      end

      def serialized
        result = {prompts:}
        result[:nextCursor] = next_cursor if next_cursor
        result
      end
    end

    ResourcesData = Data.define(:resources, :next_cursor) do
      def initialize(resources:, next_cursor: nil)
        super
      end

      def serialized
        result = {resources:}
        result[:nextCursor] = next_cursor if next_cursor
        result
      end
    end

    ResourceTemplatesData = Data.define(:resource_templates, :next_cursor) do
      def initialize(resource_templates:, next_cursor: nil)
        super
      end

      def serialized
        result = {resourceTemplates: resource_templates}
        result[:nextCursor] = next_cursor if next_cursor
        result
      end
    end

    ToolsData = Data.define(:tools, :next_cursor) do
      def initialize(tools:, next_cursor: nil)
        super
      end

      def serialized
        result = {tools:}
        result[:nextCursor] = next_cursor if next_cursor
        result
      end
    end

    def find_by_name(collection, name)
      entry = collection.find { |item| item[:name] == name }
      entry ? entry[:klass] : nil
    end
  end
end
