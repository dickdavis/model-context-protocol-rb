# model-context-protocol-rb

An implementation of the [Model Context Protocol (MCP)](https://spec.modelcontextprotocol.io/specification/2025-06-18/) in Ruby.

This SDK is experimental and subject to change. The initial focus is to implement MCP server support with the goal of providing a stable API by version `0.4`. MCP client support will follow. 

You are welcome to contribute.

## Feature Support (Server)

| Status | Feature |
|--------|---------|
| ✅ | [Prompts](https://modelcontextprotocol.io/specification/2025-06-18/server/prompts) |
| ✅ | [Resources](https://modelcontextprotocol.io/specification/2025-06-18/server/resources) |
| ✅ | [Resource Templates](https://modelcontextprotocol.io/specification/2025-06-18/server/resources#resource-templates) |
| ✅ | [Tools](https://modelcontextprotocol.io/specification/2025-06-18/server/tools) |
| ✅ | [Completion](https://modelcontextprotocol.io/specification/2025-06-18/server/utilities/completion) |
| ✅ | [Logging](https://modelcontextprotocol.io/specification/2025-06-18/server/utilities/logging) |
| ✅ | [Pagination](https://modelcontextprotocol.io/specification/2025-06-18/server/utilities/pagination) |
| ✅ | [Environment Variables](https://modelcontextprotocol.io/legacy/tools/debugging#environment-variables) |
| ✅ | [STDIO Transport](https://modelcontextprotocol.io/specification/2025-06-18/basic/transports#stdio) |
| 🚧 | [Streamable HTTP Transport](https://modelcontextprotocol.io/specification/2025-06-18/basic/transports#streamable-http) |
| ❌ | [List Changed Notification (Prompts)](https://modelcontextprotocol.io/specification/2025-06-18/server/prompts#list-changed-notification) |
| ❌ | [List Changed Notification (Resources)](https://modelcontextprotocol.io/specification/2025-06-18/server/resources#list-changed-notification) |
| ❌ | [Subscriptions (Resources)](https://modelcontextprotocol.io/specification/2025-06-18/server/resources#subscriptions) |
| ❌ | [List Changed Notification (Tools)](https://modelcontextprotocol.io/specification/2025-06-18/server/tools#list-changed-notification) |
| ❌ | [Cancellation](https://modelcontextprotocol.io/specification/2025-06-18/basic/utilities/cancellation) |
| 🚧 | [Ping](https://modelcontextprotocol.io/specification/2025-06-18/basic/utilities/ping) |
| ❌ | [Progress](https://modelcontextprotocol.io/specification/2025-06-18/basic/utilities/progress) |

## Usage

Include `model_context_protocol` in your project.

```ruby
require 'model_context_protocol'
```

### Building an MCP Server

Build a simple MCP server by registering your prompts, resources, resource templates, and tools. Then, configure and run the server.

```ruby
server = ModelContextProtocol::Server.new do |config|
  # Name of the MCP server (intended for programmatic use)
  config.name = "MCPDevelopmentServer"

  # Version of the MCP server
  config.version = "1.0.0"

  # Optional: human-readable display name for the MCP server
  config.title = "My Awesome Server"

  # Optional: instuctions for how the MCP server should be used by LLMs
  config.instructions = <<~INSTRUCTIONS
    This server provides file system access and development tools.

    Key capabilities:
    - Read and write files in the project directory
    - Execute shell commands for development tasks
    - Analyze code structure and dependencies

    Use this server when you need to interact with the local development environment.
  INSTRUCTIONS

  # Enable or disable MCP server logging
  config.logging_enabled = true

  # Configure pagination options for the following methods:
  # prompts/list, resources/list, resource_template/list, tools/list
  config.pagination = {
    default_page_size: 50,   # Default items per page
    max_page_size: 500,      # Maximum allowed page size
    cursor_ttl: 1800         # Cursor expiry in seconds (30 minutes)
  }

  # Disable pagination support (enabled by default)
  # config.pagination = false

  # Optional: require specific environment variables to be set
  config.require_environment_variable("API_KEY")

  # Optional: set environment variables programmatically
  config.set_environment_variable("DEBUG_MODE", "true")

  # Optional: provide prompts, resources, and tools with contextual variables
  config.context = {
    user_id: "123456",
    request_id: SecureRandom.uuid
  }

  # Optional: explicitly specify STDIO as the transport
  # This is not necessary as STDIO is the default transport
  # config.transport = { type: :stdio }
 
  # Optional: configure streamable HTTP transport if required
  # config.transport = {
  #   type: :streamable_http,
  #   redis_client: Redis.new(url: ENV['REDIS_URL']),
  #   session_ttl: 3600 # Optional: session timeout in seconds (default: 3600)
  # }

  # Register prompts, resources, resource templates, and tools
  config.registry = ModelContextProtocol::Server::Registry.new do
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
      register TestTool
    end
  end
end

# Start the MCP server
server.start
```

**Integration Example (Rails):**

First, set the routes:

```ruby
constraints format: :json do
  get "/mcp", to: "model_context_protocol#handle", as: :mcp_get
  post "/mcp", to: "model_context_protocol#handle", as: :mcp_post
  delete "/mcp", to: "model_context_protocol#handle", as: :mcp_delete
end
```

Then, implement a controller endpoint to handle the requests.

```ruby
require 'model_context_protocol'

class ModelContextProtocolController < ApplicationController
  def handle
    server = ModelContextProtocol::Server.new do |config|
      config.name = "MyMCPServer"
      config.title = "My MCP Server"
      config.version = "1.0.0"
      config.logging_enabled = true
      config.context = { user_id: current_user.id }
      config.registry = build_registry
      config.transport = {
        type: :streamable_http,
        redis_client: Redis.new(url: ENV['REDIS_URL']),
        request: request,
        response: response
      }
      config.instructions = <<~INSTRUCTIONS
        This server provides prompts, tools, and resources for interacting with my app.

        Key capabilities:
        - Does this one thing
        - Does this other thing
        - Oh, yeah, and it does that one thing, too

        Use this server when you need to do stuff.
      INSTRUCTIONS
    end

    result = server.start
    render json: result[:json], status: result[:status], headers: result[:headers]
  end

  private

  def build_registry
    ModelContextProtocol::Server::Registry.new do
      tools do
        # Implement user authorization logic to dynamically build registry
        register TestTool if current_user.authorized_for?(TestTool)
      end
    end
  end
end
```

### Server features

Messages from the MCP client will be routed to the appropriate custom handler. This SDK provides several classes that should be used to build your handlers.

#### Prompts

The `ModelContextProtocol::Server::Prompt` base class allows subclasses to define a prompt that the MCP client can use. Define the [appropriate metadata](https://spec.modelcontextprotocol.io/specification/2025-06-18/server/prompts/) in the `with_metadata` block.

Define any arguments using the `with_argument` block. You can mark an argument as required, and you can optionally provide a completion class. See [Completions](#completions) for more information.

Then implement the `call` method to build your prompt. Any arguments passed to the tool from the MCP client will be available in the `arguments` hash with symbol keys (e.g., `arguments[:argument_name]`), and any context values provided in the server configuration will be available in the `context` hash. Use the `respond_with` instance method to ensure your prompt responds with appropriately formatted response data.

You can also log from within your prompt by calling a valid logger level method on the `logger` and passing a string message.

This is an example prompt that returns a properly formatted response:

```ruby
class TestPrompt < ModelContextProtocol::Server::Prompt
  ToneCompletion = ModelContextProtocol::Server::Completion.define do
    hints = ["whiny", "angry", "callous", "desperate", "nervous", "sneaky"]
    values = hints.grep(/#{argument_value}/)

    respond_with values:
  end

  with_metadata do
    name "brainstorm_excuses"
    description "A prompt for brainstorming excuses to get out of something"
  end

  with_argument do
    name "undesirable_activity"
    description "The thing to get out of"
    required true
  end

  with_argument do
    name "tone"
    description "The general tone to be used in the generated excuses"
    required false
    completion ToneCompletion
  end

  def call
    logger.info("Brainstorming excuses...")
    messages = [
      {
        role: "user",
        content: {
          type: "text",
          text: "My wife wants me to: #{arguments[:undesirable_activity]}... Can you believe it?"
        }
      },
      {
        role: "assistant",
        content: {
          type: "text",
          text: "Oh, that's just downright awful. What are you going to do?"
        }
      },
      {
        role: "user",
        content: {
          type: "text",
          text: "Well, I'd like to get out of it, but I'm going to need your help."
        }
      },
      {
        role: "assistant",
        content: {
          type: "text",
          text: "Anything for you."
        }
      },
      {
        role: "user",
        content: {
          type: "text",
          text: "Can you generate some excuses for me?" + (arguments[:tone] ? "Make them as #{arguments[:tone]} as possible." : "")
        }
      }
    ]

    respond_with messages: messages
  end
end
```

#### Resources

The `ModelContextProtocol::Server::Resource` base class allows subclasses to define a resource that the MCP client can use. Define the [appropriate metadata](https://spec.modelcontextprotocol.io/specification/2025-06-18/server/resources/) in the `with_metadata` block. You can also define any [resource annotations](https://modelcontextprotocol.io/specification/2025-06-18/server/resources#annotations) in the nested `with_annotations` block.

Then, implement the `call` method to build your resource. Use the `respond_with` instance method to ensure your resource responds with appropriately formatted response data.

This is an example resource that returns a text response:

```ruby
class TestResource < ModelContextProtocol::Server::Resource
  with_metadata do
    name "top-secret-plans.txt"
    description "Top secret plans to do top secret things"
    mime_type "text/plain"
    uri "file:///top-secret-plans.txt"
  end

  def call
    respond_with :text, text: "I'm finna eat all my wife's leftovers."
  end
end
```

This is an example resource with annotations:

```ruby
class TestAnnotatedResource < ModelContextProtocol::Server::Resource
  with_metadata do
    name "annotated-document.md"
    description "A document with annotations showing priority and audience"
    mime_type "text/markdown"
    uri "file:///docs/annotated-document.md"

    with_annotations do
      audience [:user, :assistant]
      priority 0.9
      last_modified "2025-01-12T15:00:58Z"
    end
  end

  def call
    respond_with :text, text: "# Annotated Document\n\nThis document has annotations."
  end
end
```

This is an example resource that returns binary data:

```ruby
class TestBinaryResource < ModelContextProtocol::Server::Resource
  with_metadata do
    name "project-logo.png"
    description "The logo for the project"
    mime_type "image/png"
    uri "file:///project-logo.png"
  end

  def call
    # In a real implementation, we would retrieve the binary resource
    # This is a small valid base64 encoded string (represents "test")
    data = "dGVzdA=="
    respond_with :binary, blob: data
  end
end
```

#### Resource Templates

The `ModelContextProtocol::Server::ResourceTemplate` base class allows subclasses to define a resource template that the MCP client can use. Define the [appropriate metadata](https://modelcontextprotocol.io/specification/2025-06-18/server/resources#resource-templates) in the `with_metadata` block.

This is an example resource template that provides a completion for a parameter of the URI template:

```ruby
class TestResourceTemplate < ModelContextProtocol::Server::ResourceTemplate
  Completion = ModelContextProtocol::Server::Completion.define do
    hints = {
      "name" => ["top-secret-plans.txt"]
    }
    values = hints[argument_name].grep(/#{argument_value}/)

    respond_with values:
  end

  with_metadata do
    name "project-document-resource-template"
    description "A resource template for retrieving project documents"
    mime_type "text/plain"
    uri_template "file:///{name}" do
      completion :name, Completion
    end
  end
end
```

#### Tools

The `ModelContextProtocol::Server::Tool` base class allows subclasses to define a tool that the MCP client can use. Define the [appropriate metadata](https://spec.modelcontextprotocol.io/specification/2025-06-18/server/tools/) in the `with_metadata` block.

Then, implement the `call` method to build your tool. Any arguments passed to the tool from the MCP client will be available in the `arguments` hash with symbol keys (e.g., `arguments[:argument_name]`), and any context values provided in the server configuration will be available in the `context` hash. Use the `respond_with` instance method to ensure your tool responds with appropriately formatted response data.

You can also log from within your tool by calling a valid logger level method on the `logger` and passing a string message.

This is an example tool that returns a text response:

```ruby
class TestToolWithTextResponse < ModelContextProtocol::Server::Tool
  with_metadata do
    name "double"
    description "Doubles the provided number"
    input_schema do
      {
        type: "object",
        properties: {
          number: {
            type: "string"
          }
        },
        required: ["number"]
      }
    end
  end

  def call
    user_id = context[:user_id]
    number = arguments[:number].to_i
    logger.info("Silly user doesn't know how to double a number")
    calculation = number * 2
    salutation = user_id ? "User #{user_id}, " : ""
    respond_with :text, text: salutation << "#{number} doubled is #{calculation}"
  end
end
```

This is an example of a tool that returns an image:

```ruby
class TestToolWithImageResponse < ModelContextProtocol::Server::Tool
  with_metadata do
    name "custom-chart-generator"
    description "Generates a chart in various formats"
    input_schema do
      {
        type: "object",
        properties: {
          chart_type: {
            type: "string",
            description: "Type of chart (pie, bar, line)"
          },
          format: {
            type: "string",
            description: "Image format (jpg, svg, etc)"
          }
        },
        required: ["chart_type", "format"]
      }
    end
  end

  def call
    # Map format to mime type
    mime_type = case arguments[:format].downcase
    when "svg"
      "image/svg+xml"
    when "jpg", "jpeg"
      "image/jpeg"
    else
      "image/png"
    end

    # In a real implementation, we would generate an actual chart
    # This is a small valid base64 encoded string (represents "test")
    chart_data = "dGVzdA=="
    respond_with :image, data: chart_data, mime_type:
  end
end
```

If you don't provide a mime type, it will default to `image/png`.

```ruby
class TestToolWithImageResponseDefaultMimeType < ModelContextProtocol::Server::Tool
  with_metadata do
    name "other-custom-chart-generator"
    description "Generates a chart"
    input_schema do
      {
        type: "object",
        properties: {
          chart_type: {
            type: "string",
            description: "Type of chart (pie, bar, line)"
          }
        },
        required: ["chart_type"]
      }
    end
  end

  def call
    # In a real implementation, we would generate an actual chart
    # This is a small valid base64 encoded string (represents "test")
    chart_data = "dGVzdA=="
    respond_with :image, data: chart_data
  end
end
```

This is an example of a tool that returns a resource response:

```ruby
class TestToolWithResourceResponse < ModelContextProtocol::Server::Tool
  with_metadata do
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

    if resource_klass
      respond_with :resource, resource: resource_klass
    else
      respond_with :error, text: "Resource `#{name}` not found"
    end
  end
end
```

### Completions

The `ModelContextProtocol::Server::Completion` base class allows subclasses to define a completion that the MCP client can use to obtain hints or suggestions for arguments to prompts and resources.

implement the `call` method to build your completion. Use the `respond_with` instance method to ensure your completion responds with appropriately formatted response data.

This is an example completion that returns an array of values in the response:

```ruby
class TestCompletion < ModelContextProtocol::Server::Completion
  def call
    hints = {
      "message" => ["hello", "world", "foo", "bar"]
    }
    values = hints[argument_name].grep(/#{argument_value}/)

    respond_with values:
  end
end
```

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'model-context-protocol-rb'
```

And then execute:

```bash
bundle
```

Or install it yourself as:

```bash
gem install model-context-protocol-rb
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake  spec` to run the tests.

Generate an executable that you can use for testing:

```bash
bundle exec rake mcp:generate_executable
```

This will generate a `bin/dev` executable you can provide to MCP clients.

You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/dickdavis/model-context-protocol-rb.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
