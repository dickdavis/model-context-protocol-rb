# model-context-protocol-rb

An implementation of the [Model Context Protocol (MCP)](https://spec.modelcontextprotocol.io/specification/2024-11-05/) in Ruby.

This SDK is experimental and subject to change. The initial focus is to implement MCP server support with the goal of providing a stable API by version `0.4`. MCP client support will follow. 

You are welcome to contribute.

TODO's:

* [Completion](https://spec.modelcontextprotocol.io/specification/2024-11-05/server/utilities/completion/)
* [Logging](https://spec.modelcontextprotocol.io/specification/2024-11-05/server/utilities/logging/)
* [Pagination](https://spec.modelcontextprotocol.io/specification/2024-11-05/server/utilities/pagination/)
* [Prompt list changed notifications](https://spec.modelcontextprotocol.io/specification/2024-11-05/server/prompts/#list-changed-notification)
* [Resource list changed notifications](https://spec.modelcontextprotocol.io/specification/2024-11-05/server/resources/#list-changed-notification)
* [Resource subscriptions](https://spec.modelcontextprotocol.io/specification/2024-11-05/server/resources/#subscriptions)
* [Resource templates](https://spec.modelcontextprotocol.io/specification/2024-11-05/server/resources/#resource-templates)
* [Tool list changed notifications](https://spec.modelcontextprotocol.io/specification/2024-11-05/server/tools/#list-changed-notification)

## Usage

Include `model_context_protocol` in your project.

```ruby
require 'model_context_protocol'
```

### Building an MCP Server

Build a simple MCP server by registering your prompts, resources, and tools. Then, configure and run the server.

```ruby
server = ModelContextProtocol::Server.new do |config|
  config.name = "MCP Development Server"
  config.version = "1.0.0"
  config.enable_log = true
  config.registry = ModelContextProtocol::Server::Registry.new do
    prompts list_changed: true do
      register TestPrompt
    end

    resources list_changed: true, subscribe: true do
      register TestResource
    end

    tools list_changed: true do
      register TestTool
    end
  end
end

server.start
```

Messages from the MCP client will be routed to the appropriate custom handler. This SDK provides several classes that should be used to build your handlers.

#### ModelContextProtocol::Server::Prompt

The `ModelContextProtocol::Server::Prompt` base class allows subclasses to define a prompt that the MCP client can use. Define the [appropriate metadata](https://spec.modelcontextprotocol.io/specification/2024-11-05/server/prompts/) in the `with_metadata` block.

Then implement the `call` method to build your prompt. Use the `respond_with` instance method to ensure your prompt responds with appropriately formatted response data.

This is an example prompt that returns a properly formatted response:

```ruby
class TestPrompt < ModelContextProtocol::Server::Prompt
  with_metadata do
    {
      name: "Test Prompt",
      description: "A test prompt",
      arguments: [
        {
          name: "message",
          description: "The thing to do",
          required: true
        },
        {
          name: "other",
          description: "Another thing to do",
          required: false
        }
      ]
    }
  end

  def call
    messages = [
      {
        role: "user",
        content: {
          type: "text",
          text: "Do this: #{params["message"]}"
        }
      }
    ]

    respond_with messages: messages
  end
end
```

#### ModelContextProtocol::Server::Resource

The `ModelContextProtocol::Server::Resource` base class allows subclasses to define a resource that the MCP client can use. Define the [appropriate metadata](https://spec.modelcontextprotocol.io/specification/2024-11-05/server/resources/) in the `with_metadata` block, and then implement the 'call' method to build your prompt. The `call` method should return a `TextResponse` or a `BinaryResponse` data object.

```ruby
class TestResource < ModelContextProtocol::Server::Resource
  with_metadata do
    {
      name: "Test Resource",
      description: "A test resource",
      mime_type: "text/plain",
      uri: "resource://test-resource"
    }
  end

  def call
    TextResponse[resource: self, text: "Here's the data"]
  end
end
```

#### ModelContextProtocol::Server::Tool

The `ModelContextProtocol::Server::Tool` base class allows subclasses to define a tool that the MCP client can use. Define the [appropriate metadata](https://spec.modelcontextprotocol.io/specification/2024-11-05/server/tools/) in the `with_metadata` block.

Then implement the `call` method to build your prompt. Use the `respond_with` instance method to ensure your tool responds with appropriately formatted response data.

This is an example tool that returns a text response:

```ruby
class TestToolWithTextResponse < ModelContextProtocol::Server::Tool
  with_metadata do
    {
      name: "double",
      description: "Doubles the provided number",
      inputSchema: {
        type: "object",
        properties: {
          number: {
            type: "integer",
          }
        },
        required: ["number"]
      }
    }
  end

  def call
    number = params["number"].to_i
    result = number * 2
    respond_with :text, text: "#{number} doubled is #{result}"
  end
end
```

This is an example of a tool that returns an image:

```ruby
class TestToolWithImageResponse < ModelContextProtocol::Server::Tool
  with_metadata do
    {
      name: "custom-chart-generator",
      description: "Generates a chart in various formats",
      inputSchema: {
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
    }
  end

  def call
    # Map format to mime type
    mime_type = case params["format"].downcase
    when "svg"
      "image/svg+xml"
    when "jpg", "jpeg"
      "image/jpeg"
    else
      "image/png"
    end

    # In a real implementation, we would generate an actual chart
    chart_data = "base64encodeddata"
    respond_with :image, data: chart_data, mime_type:
  end
end
```

If you don't provide a mime type, it will default to `image/png`.

```ruby
class TestToolWithImageResponseDefaultMimeType < ModelContextProtocol::Server::Tool
  with_metadata do
    {
      name: "custom-chart-generator",
      description: "Generates a chart",
      inputSchema: {
        type: "object",
        properties: {
          chart_type: {
            type: "string",
            description: "Type of chart (pie, bar, line)"
          }
        },
        required: ["chart_type"]
      }
    }
  end

  def call
    # In a real implementation, we would generate an actual chart
    chart_data = "base64encodeddata"
    respond_with :image, data: chart_data
  end
end
```

This is an example of a tool that returns a resource response:

```ruby
class TestToolWithResourceResponse < ModelContextProtocol::Server::Tool
  with_metadata do
    {
      name: "document-finder",
      description: "Finds a the document with the given title",
      inputSchema: {
        type: "object",
        properties: {
          title: {
            type: "string",
            description: "The title of the document"
          }
        },
        required: ["title"]
      }
    }
  end

  def call
    title = params["title"].downcase
    # In a real implementation, we would do a lookup to get the document data
    document = "richtextdata"
    respond_with :resource, uri: "resource://document/#{title}", text: document, mime_type: "application/rtf"
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
