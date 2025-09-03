# model-context-protocol-rb

An implementation of the [Model Context Protocol (MCP)](https://spec.modelcontextprotocol.io/specification/2024-11-05/) in Ruby.

This SDK is experimental and subject to change. The initial focus is to implement MCP server support with the goal of providing a stable API by version `0.4`. MCP client support will follow. 

You are welcome to contribute.

TODO's:

* [Prompt list changed notifications](https://spec.modelcontextprotocol.io/specification/2024-11-05/server/prompts/#list-changed-notification)
* [Resource list changed notifications](https://spec.modelcontextprotocol.io/specification/2024-11-05/server/resources/#list-changed-notification)
* [Resource subscriptions](https://spec.modelcontextprotocol.io/specification/2024-11-05/server/resources/#subscriptions)
* [Tool list changed notifications](https://spec.modelcontextprotocol.io/specification/2024-11-05/server/tools/#list-changed-notification)

## Usage

Include `model_context_protocol` in your project.

```ruby
require 'model_context_protocol'
```

### Building an MCP Server

Build a simple MCP server by registering your prompts, resources, resource templates, and tools. Then, configure and run the server.

```ruby
server = ModelContextProtocol::Server.new do |config|
  config.name = "MCP Development Server"
  config.version = "1.0.0"
  config.logging_enabled = true

  # Configure pagination options for the following methods:
  # prompts/list, resources/list, resource_template/list, tools/list
  config.pagination = {
    default_page_size: 50,   # Default items per page
    max_page_size: 500,      # Maximum allowed page size
    cursor_ttl: 1800         # Cursor expiry in seconds (30 minutes)
  }

  # Disable pagination support
  # config.pagination = false

  # Environment Variables - https://modelcontextprotocol.io/docs/tools/debugging#environment-variables
  # Require specific environment variables to be set
  config.require_environment_variable("API_KEY")

  # Set environment variables programmatically
  config.set_environment_variable("DEBUG_MODE", "true")

  # Provide prompts, resources, and tools with contextual variables
  config.context = {
    user_id: "123456",
    request_id: SecureRandom.uuid
  }

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

server.start
```

### Transport Configuration

The MCP server supports different transport mechanisms for communication with clients. By default, it uses stdio (standard input/output), but you can also configure it to use streamable HTTP transport for distributed deployments.

#### Stdio Transport (Default)

When no transport is specified, the server uses stdio transport, which is suitable for single-process communication:

```ruby
server = ModelContextProtocol::Server.new do |config|
  config.name = "MCP Development Server"
  config.version = "1.0.0"
  # No transport specified - uses stdio by default
  config.registry = ModelContextProtocol::Server::Registry.new
end

server.start
```

#### Streamable HTTP Transport

For distributed deployments with load balancers and multiple server instances, use the streamable HTTP transport with Redis-backed session management:

```ruby
require 'redis'

server = ModelContextProtocol::Server.new do |config|
  config.name = "MCP Development Server"
  config.version = "1.0.0"

  # Configure streamable HTTP transport
  config.transport = {
    type: :streamable_http,
    redis_client: Redis.new(url: ENV['REDIS_URL']),
    session_ttl: 3600 # Optional: session timeout in seconds (default: 3600)
  }

  config.registry = ModelContextProtocol::Server::Registry.new
end

# For HTTP frameworks, handle the request and return the response
result = server.start
# result will be a hash like: {json: {...}, status: 200, headers: {...}}
```

**Key Features:**
- **Distributed Sessions**: Redis-backed session storage enables multiple server instances
- **Load Balancer Support**: Sessions persist across different server instances  
- **HTTP Methods**: Supports POST (requests), GET (Server-Sent Events), DELETE (cleanup)
- **Cross-Server Routing**: Messages are routed between servers via Redis pub/sub

**Integration Example (Rails):**

```ruby
class McpController < ApplicationController
  def handle
    server = ModelContextProtocol::Server.new do |config|
      config.name = "Rails MCP Server"
      config.version = "1.0.0"
      config.transport = {
        type: :streamable_http,
        redis_client: Redis.new(url: ENV['REDIS_URL']),
        request: request,
        response: response
      }
      config.registry = build_registry
    end

    result = server.start
    render json: result[:json], status: result[:status], headers: result[:headers]
  end
end
```

### Server features

Messages from the MCP client will be routed to the appropriate custom handler. This SDK provides several classes that should be used to build your handlers.

#### Prompts

The `ModelContextProtocol::Server::Prompt` base class allows subclasses to define a prompt that the MCP client can use. Define the [appropriate metadata](https://spec.modelcontextprotocol.io/specification/2024-11-05/server/prompts/) in the `with_metadata` block.

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

The `ModelContextProtocol::Server::Resource` base class allows subclasses to define a resource that the MCP client can use. Define the [appropriate metadata](https://spec.modelcontextprotocol.io/specification/2024-11-05/server/resources/) in the `with_metadata` block.

Then, implement the `call` method to build your resource. Any context values provided in the server configuration will be available in the `context` hash. Use the `respond_with` instance method to ensure your resource responds with appropriately formatted response data.

You can also log from within your resource by calling a valid logger level method on the `logger` and passing a string message.

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
    unless authorized?(context[:user_id])
      logger.info("This fool thinks he can get my top secret plans...")
      return respond_with :text, text: "Nothing to see here, move along."
    end

    respond_with :text, text: "I'm finna eat all my wife's leftovers."
  end

  private

  def authorized?(user_id)
    authorized_users = ["42", "123456"]
    authorized_users.any?(user_id)
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

The `ModelContextProtocol::Server::ResourceTemplate` base class allows subclasses to define a resource template that the MCP client can use. Define the [appropriate metadata](https://modelcontextprotocol.io/specification/2024-11-05/server/resources#resource-templates) in the `with_metadata` block.

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

The `ModelContextProtocol::Server::Tool` base class allows subclasses to define a tool that the MCP client can use. Define the [appropriate metadata](https://spec.modelcontextprotocol.io/specification/2024-11-05/server/tools/) in the `with_metadata` block.

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
    name "document-finder"
    description "Finds a the document with the given title"
    input_schema do
      {
        type: "object",
        properties: {
          title: {
            type: "string",
            description: "The title of the document"
          }
        },
        required: ["title"]
      }
    end
  end

  def call
    title = arguments[:title].downcase
    # In a real implementation, we would do a lookup to get the document data
    document = "richtextdata"
    respond_with :resource, uri: "resource://document/#{title}", text: document, mime_type: "application/rtf"
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
