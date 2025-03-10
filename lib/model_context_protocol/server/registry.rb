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

    def tools(options = {}, &block)
      @tools_options = options
      instance_eval(&block) if block
    end

    def register(klass)
      metadata = klass.metadata
      entry = {klass: klass}.merge(metadata)

      case klass.ancestors
      when ->(ancestors) { ancestors.include?(ModelContextProtocol::Server::Prompt) }
        @prompts << entry
      when ->(ancestors) { ancestors.include?(ModelContextProtocol::Server::Resource) }
        @resources << entry
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

    def find_tool(name)
      find_by_name(@tools, name)
    end

    def serialized_prompts
      {
        prompts: @prompts.map { |entry| entry.except(:klass) }
      }
    end

    def serialized_resources
      {
        resources: @resources.map { |entry| entry.except(:klass) }
      }
    end

    def serialized_tools
      {
        tools: @tools.map { |entry| entry.except(:klass) }
      }
    end

    private

    def find_by_name(collection, name)
      entry = collection.find { |item| item[:name] == name }
      entry ? entry[:klass] : nil
    end
  end
end
