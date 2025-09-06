class TestToolWithResourceResponse < ModelContextProtocol::Server::Tool
  define do
    name "resource-finder"
    description "Finds a resource given a name"
    input_schema do
      {
        type: "object",
        properties: {
          name: {
            type: "string",
            description: "The name of the resource"
          }
        },
        required: ["name"]
      }
    end
  end

  RESOURCE_MAPPINGS = {
    test_annotated_resource: TestAnnotatedResource,
    test_binary_resource: TestBinaryResource,
    test_resource: TestResource
  }.freeze

  def call
    name = arguments[:name]
    resource_klass = RESOURCE_MAPPINGS[name.downcase.to_sym]
    unless resource_klass
      return respond_with :error, text: "Resource `#{name}` not found"
    end

    resource_data = resource_klass.call

    respond_with content: embedded_resource_content(resource: resource_data)
  end
end
