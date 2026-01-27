# model-context-protocol-rb

An implementation of the [Model Context Protocol (MCP)](https://spec.modelcontextprotocol.io/specification/2025-06-18/) in Ruby.

Provides simple abstractions that allow you to serve prompts, resources, resource templates, and tools via MCP locally (stdio) or in production (streamable HTTP backed by Redis) with minimal effort.

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
| ✅ | [Streamable HTTP Transport](https://modelcontextprotocol.io/specification/2025-06-18/basic/transports#streamable-http) |
| ❌ | [List Changed Notification (Prompts)](https://modelcontextprotocol.io/specification/2025-06-18/server/prompts#list-changed-notification) |
| ❌ | [List Changed Notification (Resources)](https://modelcontextprotocol.io/specification/2025-06-18/server/resources#list-changed-notification) |
| ❌ | [Subscriptions (Resources)](https://modelcontextprotocol.io/specification/2025-06-18/server/resources#subscriptions) |
| ❌ | [List Changed Notification (Tools)](https://modelcontextprotocol.io/specification/2025-06-18/server/tools#list-changed-notification) |
| ✅ | [Cancellation](https://modelcontextprotocol.io/specification/2025-06-18/basic/utilities/cancellation) |
| ✅ | [Ping](https://modelcontextprotocol.io/specification/2025-06-18/basic/utilities/ping) |
| ✅ | [Progress](https://modelcontextprotocol.io/specification/2025-06-18/basic/utilities/progress) |

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

For detailed installation instructions, see the [Installation wiki page](https://github.com/dickdavis/model-context-protocol-rb/wiki/Installation).

## Building an MCP Server

> **Quick Start:** For a complete Rails integration example, see the [Quick Start with Rails](https://github.com/dickdavis/model-context-protocol-rb/wiki/Quick-Start-with-Rails) guide.

Build a simple MCP server by registering your prompts, resources, resource templates, and tools. Then, configure and run the server. Messages from the MCP client will be routed to the appropriate custom handler. This SDK provides several classes that should be used to build your handlers.

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
  #   env: request.env,
  #   session_ttl: 3600 # Optional: session timeout in seconds (default: 3600)
  # }

  # Register prompts, resources, resource templates, and tools
  config.registry = ModelContextProtocol::Server::Registry.new do
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
      register TestTool
    end
  end
end

# Start the MCP server
server.start
```

For complete configuration details including server options, transport setup, Redis configuration, and logging options, see the [Building an MCP Server](https://github.com/dickdavis/model-context-protocol-rb/wiki/Building-an-MCP-Server) wiki page.

## Prompts

Define prompts that MCP clients can use to generate contextual message sequences.

```ruby
class TestPrompt < ModelContextProtocol::Server::Prompt
  define do
    name "brainstorm_excuses"
    description "A prompt for brainstorming excuses"
    argument { name "tone"; required false }
  end

  def call
    messages = message_history do
      user_message { text_content(text: "Generate excuses with #{arguments[:tone]} tone") }
    end
    respond_with messages:
  end
end
```

Key features:
- Define arguments with validation and completion hints
- Build message histories with user and assistant messages
- Support for text, image, audio, and embedded resource content

For complete documentation and examples, see the [Prompts](https://github.com/dickdavis/model-context-protocol-rb/wiki/Prompts) wiki page.

## Resources

Expose data and content to MCP clients through defined resources.

```ruby
class TestResource < ModelContextProtocol::Server::Resource
  define do
    name "config.json"
    description "Application configuration"
    mime_type "application/json"
    uri "file:///config.json"
  end

  def call
    respond_with text: { setting: "value" }.to_json
  end
end
```

Key features:
- Define metadata including MIME type and URI
- Return text or binary content
- Add annotations for audience and priority

For complete documentation and examples, see the [Resources](https://github.com/dickdavis/model-context-protocol-rb/wiki/Resources) wiki page.

## Resource Templates

Define parameterized resources with URI templates that clients can instantiate.

```ruby
class TestResourceTemplate < ModelContextProtocol::Server::ResourceTemplate
  define do
    name "document-template"
    description "Template for retrieving documents"
    mime_type "text/plain"
    uri_template "file:///{name}" do
      completion :name, ["readme.txt", "config.json"]
    end
  end
end
```

Key features:
- Define URI templates with parameters
- Provide completion hints for template parameters

For complete documentation and examples, see the [Resource Templates](https://github.com/dickdavis/model-context-protocol-rb/wiki/Resource-Templates) wiki page.

## Tools

Create callable functions that MCP clients can invoke with validated inputs.

```ruby
class TestToolWithStructuredContentResponse < ModelContextProtocol::Server::Tool
  define do
    # The name of the tool for programmatic use
    name "get_weather_data"
    # The human-readable tool name for display in UI
    title "Weather Data Retriever"
    # A short description of what the tool does
    description "Get current weather data for a location"
    # The JSON schema for validating tool inputs
    input_schema do
      {
        type: "object",
        properties: {
          location: {
            type: "string",
            description: "City name or zip code"
          }
        },
        required: ["location"]
      }
    end
    # The JSON schema for validating structured content
    output_schema do
      {
        type: "object",
        properties: {
          temperature: {
            type: "number",
            description: "Temperature in celsius"
          },
          conditions: {
            type: "string",
            description: "Weather conditions description"
          },
          humidity: {
            type: "number",
            description: "Humidity percentage"
          }
        },
        required: ["temperature", "conditions", "humidity"]
      }
    end
  end

  def call
    # Use values provided by the server as context
    user_id = context[:user_id]
    client_logger.info("Initiating request for user #{user_id}...")

    # Use values provided by clients as tool arguments
    location = arguments[:location]
    client_logger.info("Getting weather data for #{location}...")

    # Returns a hash that validates against the output schema
    weather_data = get_weather_data(location)

    # Respond with structured content
    respond_with structured_content: weather_data
  end

  private

  # Simulate calling an external API to get weather data for the provided input
  def get_weather_data(location)
    {
      temperature: 22.5,
      conditions: "Partly cloudy",
      humidity: 65
    }
  end
end
```

Key features:
- Define input and output JSON schemas
- Return text, image, audio, or embedded resource content
- Support for structured content responses
- Cancellable and progressable operations

For complete documentation and 7 detailed examples, see the [Tools](https://github.com/dickdavis/model-context-protocol-rb/wiki/Tools) wiki page.

## Completions

Provide argument completion hints for prompts and resource templates.

```ruby
class TestCompletion < ModelContextProtocol::Server::Completion
  def call
    hints = { "tone" => ["whiny", "angry", "nervous"] }
    values = hints[argument_name].grep(/#{argument_value}/)
    respond_with values:
  end
end
```

For complete documentation, see the [Completions](https://github.com/dickdavis/model-context-protocol-rb/wiki/Completions) wiki page.

## Testing with RSpec

This gem provides custom RSpec matchers and helpers for testing your MCP handlers.

```ruby
require "model_context_protocol/rspec"
ModelContextProtocol::RSpec.configure!

RSpec.describe WeatherTool, type: :mcp do
  it "returns weather data" do
    response = call_mcp_tool(WeatherTool, { location: "New York" })
    expect(response).to be_valid_mcp_tool_response
    expect(response).to have_text_content(/temperature/)
  end
end
```

Key features:
- Helper methods: `call_mcp_tool`, `call_mcp_prompt`, `call_mcp_resource`
- Class definition matchers: `be_valid_mcp_class(:tool)`
- Response matchers for text, image, audio, and structured content
- Prompt and resource-specific matchers

For complete matcher documentation and examples, see the [Testing with RSpec](https://github.com/dickdavis/model-context-protocol-rb/wiki/Testing-with-RSpec) wiki page.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `bundle exec rspec` to run the tests.

### Generate Development Servers

Generate executables that you can use for testing:

```bash
# generates bin/dev for STDIO transport
bundle exec rake mcp:generate_stdio_server

# generates bin/dev-http for streamable HTTP transport
bundle exec rake mcp:generate_streamable_http_server
```

If you need to test with HTTPS (e.g., for clients that require SSL), generate self-signed certificates:

```bash
# Create SSL directory and generate certificates
mkdir -p tmp/ssl
openssl req -x509 -newkey rsa:4096 -keyout tmp/ssl/server.key -out tmp/ssl/server.crt -days 365 -nodes -subj "/C=US/ST=Dev/L=Dev/O=Dev/CN=localhost"
```

The HTTP server supports both HTTP and HTTPS:

```bash
# Run HTTP server (default)
bin/dev-http

# Run HTTPS server (requires SSL certificates in tmp/ssl/)
SSL=true bin/dev-http
```

You can also run `bin/console` for an interactive prompt that will allow you to experiment. Execute command `rp` to reload the project.

To install this gem onto your local machine, run `bundle exec rake install`.

### Releases

To release a new version, update the version number in `version.rb`, and submit a PR. After the PR has been merged to main, run `bundle exec rake release`, which will:
* create a git tag for the version,
* push the created tag,
* and push the `.gem` file to [rubygems.org](https://rubygems.org).

Then, draft and publish release notes in Github.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/dickdavis/model-context-protocol-rb.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
