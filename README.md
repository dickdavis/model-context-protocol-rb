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

Include `model-context-protocol-rb` in your project.

```ruby
require 'model-context-protocol-rb'
```

### Building an MCP Server

Build a simple MCP server by routing methods to your custom handlers. Then, configure and run the server.

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

The `Prompt` class is used to define a prompt that the MCP client can use. Define the [appropriate metadata](https://spec.modelcontextprotocol.io/specification/2024-11-05/server/prompts/) in the `with_metadata` block, and then implement the call method to build your prompt. The `call` method should return a `Response` data object.

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

    Response[messages:, prompt: self]
  end
end
```

#### ModelContextProtocol::Server::Resource

The `Resource` class is used to define a resource that the MCP client can use. Define the [appropriate metadata](https://spec.modelcontextprotocol.io/specification/2024-11-05/server/resources/) in the `with_metadata` block, and then implement the 'call' method to build your prompt. The `call` method should return a `TextResponse` or a `BinaryResponse` data object.

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

The `Tool` class is used to define a tool that the MCP client can use. Define the [appropriate metadata](https://spec.modelcontextprotocol.io/specification/2024-11-05/server/tools/) in the `with_metadata` block, and then implement the `call` method to build your prompt. The `call` method should return a `TextResponse`, `ImageResponse`, `ResourceResponse`, or `ToolErrorResponse` data object.

```ruby
class TestTool < ModelContextProtocol::Server::Tool
  with_metadata do
    {
      name: "test-tool",
      description: "A test tool",
      inputSchema: {
        type: "object",
        properties: {
          message: {
            type: "string"
          }
        },
        required: ["message"]
      }
    }
  end

  def call
    TextResponse[text: "You said: #{params["message"]}"]
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

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake  spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/dickdavis/model-context-protocol-rb.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
