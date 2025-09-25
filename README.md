# model-context-protocol-rb

An implementation of the [Model Context Protocol (MCP)](https://spec.modelcontextprotocol.io/specification/2025-06-18/) in Ruby.

Provides simple abstractions that allow you to serve prompts, resources, resource templates, and tools via MCP locally (stdio) or in production (streamable HTTP backed by Redis) with minimal effort.

## Table of Contents

- [Feature Support (Server)](#feature-support-server)
- [Quick Start with Rails](#quick-start-with-rails)
- [Installation](#installation)
- [Building an MCP Server](#building-an-mcp-server)
  - [Server Configuration Options](#server-configuration-options)
  - [Pagination Configuration Options](#pagination-configuration-options)
  - [Transport Configuration Options](#transport-configuration-options)
  - [Redis Configuration](#redis-configuration)
  - [Registry Configuration Options](#registry-configuration-options)
- [Prompts](#prompts)
- [Resources](#resources)
- [Resource Templates](#resource-templates)
- [Tools](#tools)
- [Completions](#completions)
- [Development](#development)
- [Contributing](#contributing)
- [License](#license)

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

## Quick Start with Rails

The `model-context-protocol-rb` works out of the box with any valid Rack request. Currently, this project has no plans for building a deeper Rails integration, but it is fairly simple to build it out yourself. To support modern application deployments across multiple servers, the streamable HTTP transport requires Redis as an external dependency.

Here's an example of how you can easily integrate with Rails.

First, configure Redis in an initializer:

```ruby
# config/initializers/model_context_protocol.rb
require "model_context_protocol"

ModelContextProtocol::Server.configure_redis do |config|
  config.redis_url = ENV.fetch("REDIS_URL", "redis://localhost:6379/0")
  config.pool_size = 20
  config.pool_timeout = 5
  config.enable_reaper = true
  config.reaper_interval = 60
  config.idle_timeout = 300
end
```

Then, set the routes:

```ruby
constraints format: :json do
  get "/mcp", to: "model_context_protocol#handle", as: :mcp_get
  post "/mcp", to: "model_context_protocol#handle", as: :mcp_post
  delete "/mcp", to: "model_context_protocol#handle", as: :mcp_delete
end
```

Then, implement a controller endpoint to handle the requests.

```ruby
class ModelContextProtocolController < ActionController::API
  include ActionController::Live

  before_action :authenticate_user

  def handle
    server = ModelContextProtocol::Server.new do |config|
      config.name = "MyMCPServer"
      config.title = "My MCP Server"
      config.version = "1.0.0"
      config.registry = build_registry
      config.context = {
        user_id: current_user.id,
        request_id: request.id
      }
      config.transport = {
        type: :streamable_http,
        env: request.env
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
    handle_mcp_response(result)
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

  def handle_mcp_response(result)
    if result[:headers]&.dig("Content-Type") == "text/event-stream"
      setup_streaming_headers
      stream_response(result[:stream_proc])
    else
      render_json_response(result)
    end
  end

  def setup_streaming_headers
    response.headers.merge!(
      "Content-Type" => "text/event-stream",
      "Cache-Control" => "no-cache",
      "Connection" => "keep-alive"
    )
  end

  def stream_response(stream_proc)
    stream_proc&.call(response.stream)
  ensure
    response.stream.close rescue nil
  end

  def render_json_response(result)
    render json: result[:json],
      status: result[:status] || 200,
      headers: result[:headers] || {}
  end
end
```

Read more about the [server configuration options](building-an-mcp-server) to better understand how you can customize your MCP server.

From here, you can get started building [prompts](#prompts), [resources](#resources), [resource templates](#resource-templates), and [tools](#tools).

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

## Building an MCP Server

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

### Server Configuration Options

The following table details all available configuration options for the MCP server:

| Option | Type | Required | Default | Description |
|--------|------|----------|---------|-------------|
| `name` | String | Yes | - | Name of the MCP server for programmatic use |
| `version` | String | Yes | - | Version of the MCP server |
| `title` | String | No | - | Human-readable display name for the MCP server |
| `instructions` | String | No | - | Instructions for how the MCP server should be used by LLMs |
| `pagination` | Hash/Boolean | No | See pagination table | Pagination configuration (or `false` to disable) |
| `context` | Hash | No | `{}` | Contextual variables available to prompts, resources, and tools |
| `transport` | Hash | No | `{ type: :stdio }` | Transport configuration |
| `registry` | Registry | Yes | - | Registry containing prompts, resources, and tools |

### Pagination Configuration Options

When `pagination` is set to a Hash, the following options are available:

| Option | Type | Required | Default | Description |
|--------|------|----------|---------|-------------|
| `default_page_size` | Integer | No | `50` | Default number of items per page |
| `max_page_size` | Integer | No | `500` | Maximum allowed page size |
| `cursor_ttl` | Integer | No | `1800` | Cursor expiry time in seconds (30 minutes) |

**Note:** Set `config.pagination = false` to completely disable pagination support.

### Transport Configuration Options

The transport configuration supports two types: `:stdio` (default) and `:streamable_http`.

#### STDIO Transport

```ruby
config.transport = { type: :stdio }  # This is the default, can be omitted
```

#### Streamable HTTP Transport

```ruby
config.transport = { type: :streamable_http, env: request.env }
```

When using `:streamable_http` transport, the following options are available:

| Option | Type | Required | Default | Description |
|--------|------|----------|---------|-------------|
| `type` | Symbol | Yes | `:stdio` | Must be `:streamable_http` for HTTP transport |
| `session_ttl` | Integer | No | `3600` | Session timeout in seconds (1 hour) |
| `env` | Hash | No | - | Rack environment hash (for Rails integration) |

### Redis Configuration

The `:streamable_http` transport requires Redis to be configured globally before use:

```ruby
ModelContextProtocol::Server.configure_redis do |config|
  config.redis_url = ENV.fetch('REDIS_URL')
  config.pool_size = 20
  config.pool_timeout = 5
  config.enable_reaper = true
  config.reaper_interval = 60
  config.idle_timeout = 300
end
```

| Option | Type | Required | Default | Description |
|--------|------|----------|---------|-------------|
| `redis_url` | String | Yes | - | Redis connection URL |
| `pool_size` | Integer | No | `20` | Connection pool size |
| `pool_timeout` | Integer | No | `5` | Pool checkout timeout in seconds |
| `enable_reaper` | Boolean | No | `true` | Enable connection reaping |
| `reaper_interval` | Integer | No | `60` | Reaper check interval in seconds |
| `idle_timeout` | Integer | No | `300` | Idle connection timeout in seconds |

### Registry Configuration Options

The registry is configured using `ModelContextProtocol::Server::Registry.new` and supports the following block types:

| Block Type | Options | Description |
|------------|---------|-------------|
| `prompts` | `list_changed: Boolean` | Register prompt handlers with optional list change notifications |
| `resources` | `list_changed: Boolean`, `subscribe: Boolean` | Register resource handlers with optional list change notifications and subscriptions |
| `resource_templates` | - | Register resource template handlers |
| `tools` | `list_changed: Boolean` | Register tool handlers with optional list change notifications |

Within each block, use `register ClassName` to register your handlers.

**Example:**
```ruby
config.registry = ModelContextProtocol::Server::Registry.new do
  prompts list_changed: true do
    register MyPrompt
    register AnotherPrompt
  end

  resources list_changed: true, subscribe: true do
    register MyResource
  end

  tools do
    register MyTool
  end
end
```

---

## Prompts

The `ModelContextProtocol::Server::Prompt` base class allows subclasses to define a prompt that the MCP client can use.

Define the prompt properties and then implement the `call` method to build your prompt. Any arguments passed to the tool from the MCP client will be available in the `arguments` hash with symbol keys (e.g., `arguments[:argument_name]`), and any context values provided in the server configuration will be available in the `context` hash. Use the `respond_with` instance method to ensure your prompt responds with appropriately formatted response data.

You can also log from within your prompt by calling a valid logger level method on the `logger` and passing a string message.

### Prompt Definition

Use the `define` block to set [prompt properties](https://spec.modelcontextprotocol.io/specification/2025-06-18/server/prompts/) and configure arguments.

| Property | Description |
|----------|-------------|
| `name` | The programmatic name of the prompt |
| `title` | Human-readable display name |
| `description` | Short description of what the prompt does |
| `argument` | Define an argument block with name, description, required flag, and completion |

### Argument Definition

Define any arguments using `argument` blocks nested within the `define` block. You can mark an argument as required, and you can optionally provide a completion class. See [Completions](#completions) for more information.

| Property | Description |
|----------|-------------|
| `name` | The name of the argument |
| `description` | A short description of the argument |
| `required` | Whether the argument is required (boolean) |
| `completion` | Available hints for completions (array or completion class) |

### Prompt Methods

Define your prompt properties and arguments, implement the `call` method using the `message_history` DSL to build prompt messages and `respond_with` to serialize them. You can wrap long running operations in a `cancellable` block to allow clients to cancel the request. Also, you can automatically send progress notifications to clients by wrapping long-running operations in a `progressable` block.

| Method | Context | Description |
|--------|---------|-------------|
| `define` | Class definition | Block for defining prompt metadata and arguments |
| `call` | Instance method | Main method to implement prompt logic and build response |
| `cancellable` | Within `call` | Wrap long-running operations to allow client cancellation (e.g., `cancellable { slow_operation }`) |
| `progressable` | Within `call` | Wrap long-running operations to send clients progress notifications (e.g., `progressable { slow_operation }`) |
| `message_history` | Within `call` | DSL method to build an array of user and assistant messages |
| `respond_with` | Within `call` | Return properly formatted response data (e.g., `respond_with messages:`) |

### Message History DSL

Build a message history using the an intuitive DSL, creating an ordered history of user and assistant messages with flexible content blocks that can include text, image, audio, embedded resources, and resource links.

| Method | Context | Description |
|--------|---------|-------------|
| `user_message` | Within `message_history` | Create a message with user role |
| `assistant_message` | Within `message_history` | Create a message with assistant role |

### Content Blocks

Use content blocks to properly format the content included in messages.

| Method | Context | Description |
|--------|---------|-------------|
| `text_content` | Within message blocks | Create text content block |
| `image_content` | Within message blocks | Create image content block (requires `data:` and `mime_type:`) |
| `audio_content` | Within message blocks | Create audio content block (requires `data:` and `mime_type:`) |
| `embedded_resource_content` | Within message blocks | Create embedded resource content block (requires `resource:`) |
| `resource_link` | Within message blocks | Create resource link content block (requires `name:` and `uri:`) |

### Available Instance Variables

The `arguments` passed from an MCP client are available, as well as the `context` values passed in at server initialization.

| Variable | Context | Description |
|----------|---------|-------------|
| `arguments` | Within `call` | Hash containing client-provided arguments (symbol keys) |
| `context` | Within `call` | Hash containing server configuration context values |
| `logger` | Within `call` | Logger instance for logging (e.g., `logger.info("message")`) |

### Examples

This is an example prompt that returns a properly formatted response:

```ruby
class TestPrompt < ModelContextProtocol::Server::Prompt
  define do
    # The name of the prompt for programmatic use
    name "brainstorm_excuses"
    # The human-readable prompt name for display in UI
    title "Brainstorm Excuses"
    # A short description of what the tool does
    description "A prompt for brainstorming excuses to get out of something"

    # Define arguments to be used with your prompt
    argument do
      # The name of the argument
      name "tone"
      # A short description of the argument
      description "The general tone to be used in the generated excuses"
      # If the argument is required
      required false
      # Available hints for completions
      completion ["whiny", "angry", "callous", "desperate", "nervous", "sneaky"]
    end

    argument do
      name "undesirable_activity"
      description "The thing to get out of"
      required true
    end
  end

  # You can optionally define a custom completion for an argument and pass it to completions.
  # ToneCompletion = ModelContextProtocol::Server::Completion.define do
  #   hints = ["whiny", "angry", "callous", "desperate", "nervous", "sneaky"]
  #   values = hints.grep(/#{argument_value}/)
  #   respond_with values:
  # end
  #   ...
  # define do
  #   argument do
  #     name "tone"
  #     description "The general tone to be used in the generated excuses"
  #     required false
  #     completion ToneCompletion
  #   end
  # end

  # The call method is invoked by the MCP Server to generate a response to resource/read requests
  def call
    # You can use the logger
    logger.info("Brainstorming excuses...")

    # Build an array of user and assistant messages
    messages = message_history do
      # Create a message with the user role
      user_message do
        # Use any type of content block in a message (text, image, audio, embedded_resource, or resource_link)
        text_content(text: "My wife wants me to: #{arguments[:undesirable_activity]}... Can you believe it?")
      end

      # You can also create messages with the assistant role
      assistant_message do
        text_content(text: "Oh, that's just downright awful. How can I help?")
      end

      user_message do
        # Reference any inputs from the client by accessing the appropriate key in the arguments hash
        text_content(text: "Can you generate some excuses for me?" + (arguments[:tone] ? " Make them as #{arguments[:tone]} as possible." : ""))
      end
    end

    # Respond with the messages
    respond_with messages:
  end
end
```

---

## Resources

The `ModelContextProtocol::Server::Resource` base class allows subclasses to define a resource that the MCP client can use.

Define the resource properties and optionally annotations, then implement the `call` method to build your resource. Use the `respond_with` instance method to ensure your resource responds with appropriately formatted response data.

### Resource Definition

Use the `define` block to set [resource properties](https://spec.modelcontextprotocol.io/specification/2025-06-18/server/resources/) and configure annotations.

| Property | Description |
|----------|-------------|
| `name` | The name of the resource |
| `title` | Human-readable display name |
| `description` | Short description of what the resource contains |
| `mime_type` | MIME type of the resource content |
| `uri` | URI identifier for the resource |
| `annotations` | Block for defining resource annotations |

### Annotation Definition

Define any [resource annotations](https://modelcontextprotocol.io/specification/2025-06-18/server/resources#annotations) using an `annotations` block nested within the `define` block.

| Property | Description |
|----------|-------------|
| `audience` | Target audience for the resource (array of symbols like `[:user, :assistant]`) |
| `priority` | Priority level (numeric value, e.g., `0.9`) |
| `last_modified` | Last modified timestamp (ISO 8601 string) |

### Resource Methods

Define your resource properties and annotations, implement the `call` method to build resource content and `respond_with` to serialize the response. You can wrap long running operations in a `cancellable` block to allow clients to cancel the request. Also, you can automatically send progress notifications to clients by wrapping long-running operations in a `progressable` block.

| Method | Context | Description |
|--------|---------|-------------|
| `define` | Class definition | Block for defining resource metadata and annotations |
| `call` | Instance method | Main method to implement resource logic and build response |
| `cancellable` | Within `call` | Wrap long-running operations to allow client cancellation (e.g., `cancellable { slow_operation }`) |
| `progressable` | Within `call` | Wrap long-running operations to send clients progress notifications (e.g., `progressable { slow_operation }`) |
| `respond_with` | Within `call` | Return properly formatted response data (e.g., `respond_with text:` or `respond_with binary:`) |

### Available Instance Variables

Resources are stateless and only have access to their configured properties.

| Variable | Context | Description |
|----------|---------|-------------|
| `mime_type` | Within `call` | The configured MIME type for this resource |
| `uri` | Within `call` | The configured URI identifier for this resource |

### Examples

This is an example resource that returns a text response:

```ruby
class TestResource < ModelContextProtocol::Server::Resource
  define do
    name "top-secret-plans.txt"
    title "Top Secret Plans"
    description "Top secret plans to do top secret things"
    mime_type "text/plain"
    uri "file:///top-secret-plans.txt"
  end

  def call
    respond_with text: "I'm finna eat all my wife's leftovers."
  end
end
```

This is an example resource with annotations:

```ruby
class TestAnnotatedResource < ModelContextProtocol::Server::Resource
  define do
    name "annotated-document.md"
    description "A document with annotations showing priority and audience"
    mime_type "text/markdown"
    uri "file:///docs/annotated-document.md"
    annotations do
      audience [:user, :assistant]
      priority 0.9
      last_modified "2025-01-12T15:00:58Z"
    end
  end

  def call
    respond_with text: "# Annotated Document\n\nThis document has annotations."
  end
end
```

This is an example resource that returns binary data:

```ruby
class TestBinaryResource < ModelContextProtocol::Server::Resource
  define do
    name "project-logo.png"
    description "The logo for the project"
    mime_type "image/png"
    uri "file:///project-logo.png"
  end

  def call
    # In a real implementation, we would retrieve the binary resource
    # This is a small valid base64 encoded string (represents "test")
    data = "dGVzdA=="
    respond_with binary: data
  end
end
```

---

## Resource Templates

The `ModelContextProtocol::Server::ResourceTemplate` base class allows subclasses to define a resource template that the MCP client can use.

Define the resource template properties and URI template with optional parameter completions. Resource templates are used to define parameterized resources that clients can instantiate.

### Resource Template Definition

Use the `define` block to set [resource template properties](https://modelcontextprotocol.io/specification/2025-06-18/server/resources#resource-templates).

| Property | Description |
|----------|-------------|
| `name` | The name of the resource template |
| `description` | Short description of what the template provides |
| `mime_type` | MIME type of resources created from this template |
| `uri_template` | URI template with parameters (e.g., `"file:///{name}"`) |

### URI Template Configuration

Define the URI template and configure parameter completions within the `uri_template` block.

| Method | Context | Description |
|--------|---------|-------------|
| `completion` | Within `uri_template` block | Define completion for a URI parameter (e.g., `completion :name, ["value1", "value2"]`) |

### Resource Template Methods

Resource templates only use the `define` method to configure their properties - they don't have a `call` method.

| Method | Context | Description |
|--------|---------|-------------|
| `define` | Class definition | Block for defining resource template metadata and URI template |

### Examples

This is an example resource template that provides a completion for a parameter of the URI template:

```ruby
class TestResourceTemplate < ModelContextProtocol::Server::ResourceTemplate
  define do
    name "project-document-resource-template"
    description "A resource template for retrieving project documents"
    mime_type "text/plain"
    uri_template "file:///{name}" do
      completion :name, ["top-secret-plans.txt"]
    end
  end

  # You can optionally define a custom completion for an argument and pass it to completions.
  # Completion = ModelContextProtocol::Server::Completion.define do
  #   hints = {
  #     "name" => ["top-secret-plans.txt"]
  #   }
  #   values = hints[argument_name].grep(/#{argument_value}/)

  #   respond_with values:
  # end

  # define do
  #   name "project-document-resource-template"
  #   description "A resource template for retrieving project documents"
  #   mime_type "text/plain"
  #   uri_template "file:///{name}" do
  #     completion :name, Completion
  #   end
  # end
end
```

---

## Tools

The `ModelContextProtocol::Server::Tool` base class allows subclasses to define a tool that the MCP client can use.

Define the tool properties and schemas, then implement the `call` method to build your tool response. Arguments from the MCP client and server context are available, along with logging capabilities.

### Tool Definition

Use the `define` block to set [tool properties](https://spec.modelcontextprotocol.io/specification/2025-06-18/server/tools/) and configure schemas.

| Property | Description |
|----------|-------------|
| `name` | The programmatic name of the tool |
| `title` | Human-readable display name |
| `description` | Short description of what the tool does |
| `input_schema` | JSON schema block for validating tool inputs |
| `output_schema` | JSON schema block for validating structured content outputs |

### Tool Methods

Define your tool properties and schemas, implement the `call` method using content helpers and `respond_with` to serialize responses. You can wrap long running operations in a `cancellable` block to allow clients to cancel the request. Also, you can automatically send progress notifications to clients by wrapping long-running operations in a `progressable` block.

| Method | Context | Description |
|--------|---------|-------------|
| `define` | Class definition | Block for defining tool metadata and schemas |
| `call` | Instance method | Main method to implement tool logic and build response |
| `cancellable` | Within `call` | Wrap long-running operations to allow client cancellation (e.g., `cancellable { slow_operation }`) |
| `progressable` | Within `call` | Wrap long-running operations to send clients progress notifications (e.g., `progressable { slow_operation }`) |
| `respond_with` | Within `call` | Return properly formatted response data with various content types |

### Content Blocks

Use content blocks to properly format the content included in tool responses.

| Method | Context | Description |
|--------|---------|-------------|
| `text_content` | Within `call` | Create text content block |
| `image_content` | Within `call` | Create image content block (requires `data:` and `mime_type:`) |
| `audio_content` | Within `call` | Create audio content block (requires `data:` and `mime_type:`) |
| `embedded_resource_content` | Within `call` | Create embedded resource content block (requires `resource:`) |
| `resource_link` | Within `call` | Create resource link content block (requires `name:` and `uri:`) |

### Response Types

Tools can return different types of responses using `respond_with`.

| Response Type | Usage | Description |
|---------------|-------|-------------|
| `structured_content:` | `respond_with structured_content: data` | Return structured data validated against output schema |
| `content:` | `respond_with content: content_block` | Return single content block |
| `content:` | `respond_with content: [content_blocks]` | Return array of mixed content blocks |
| `error:` | `respond_with error: "message"` | Return tool error response |

### Available Instance Variables

Arguments from MCP clients and server context are available, along with logging capabilities.

| Variable | Context | Description |
|----------|---------|-------------|
| `arguments` | Within `call` | Hash containing client-provided arguments (symbol keys) |
| `context` | Within `call` | Hash containing server configuration context values |
| `logger` | Within `call` | Logger instance for logging (e.g., `logger.info("message")`) |

### Examples

This is an example of a tool that returns structured content validated by an output schema:

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
    logger.info("Initiating request for user #{user_id}...")

    # Use values provided by clients as tool arguments
    location = arguments[:location]
    logger.info("Getting weather data for #{location}...")

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

This is an example tool that returns a text response:

```ruby
class TestToolWithTextResponse < ModelContextProtocol::Server::Tool
  define do
    name "double"
    title "Number Doubler"
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
    logger.info("Silly user doesn't know how to double a number")
    number = arguments[:number].to_i
    calculation = number * 2

    user_id = context[:user_id]
    salutation = user_id ? "User #{user_id}, " : ""
    text_content = text_content(text: salutation << "#{number} doubled is #{calculation}")

    respond_with content: text_content
  end
end
```

This is an example of a tool that returns an image:

```ruby
class TestToolWithImageResponse < ModelContextProtocol::Server::Tool
  define do
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
    data = "dGVzdA=="
    image_content = image_content(data:, mime_type:)
    respond_with content: image_content
  end
end
```

This is an example of a tool that returns an embedded resource response:

```ruby
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
```

This is an example of a tool that returns mixed content:

```ruby
class TestToolWithMixedContentResponse < ModelContextProtocol::Server::Tool
  define do
    name "get_temperature_history"
    description "Gets comprehensive temperature history for a zip code"
    input_schema do
      {
        type: "object",
        properties: {
          zip: {
            type: "string"
          }
        },
        required: ["zip"]
      }
    end
  end

  def call
    logger.info("Getting comprehensive temperature history data")

    zip = arguments[:zip]
    temperature_history = retrieve_temperature_history(zip:)
    temperature_history_block = text_content(text: temperature_history.join(", "))

    temperature_chart = generate_weather_history_chart(temperature_history)
    temperature_chart_block = image_content(
      data: temperature_chart[:base64_chart_data],
      mime_type: temperature_chart[:mime_type]
    )

    respond_with content: [temperature_history_block, temperature_chart_block]
  end

  private

  def retrieve_temperature_history(zip:)
    # Simulates a call to an API or DB to retrieve weather history
    [85.2, 87.4, 89.0, 95.3, 96.0]
  end

  def generate_weather_history_chart(history)
    # SImulate a call to generate a chart given the weather history
    {
      base64_chart_data: "dGVzdA==",
      mime_type: "image/png"
    }
  end
end
```

This is an example of a tool that returns a tool error response:

```ruby
class TestToolWithToolErrorResponse < ModelContextProtocol::Server::Tool
  define do
    name "api-caller"
    description "Makes calls to external APIs"
    input_schema do
      {
        type: "object",
        properties: {
          api_endpoint: {
            type: "string",
            description: "API endpoint URL"
          },
          method: {
            type: "string",
            description: "HTTP method (GET, POST, etc)"
          }
        },
        required: ["api_endpoint", "method"]
      }
    end
  end

  def call
    # Simulate an API call failure
    respond_with error: "Failed to call API at #{arguments[:api_endpoint]}: Connection timed out"
  end
end
```

This is an example of a tool that allows a client to cancel a long-running operation:

```ruby
class TestToolWithCancellableSleep < ModelContextProtocol::Server::Tool
  define do
    name "cancellable_sleep"
    title "Cancellable Sleep Tool"
    description "Sleep for 3 seconds with cancellation support"
    input_schema do
      {
        type: "object",
        properties: {},
        additionalProperties: false
      }
    end
  end

  def call
    logger.info("Starting 3 second sleep operation")

    result = cancellable do
      sleep 3
      "Sleep completed successfully"
    end

    respond_with content: text_content(text: result)
  end
end
```

This is an example of a tool that automatically sends progress notifications to the client and allows the client to cancel the operation:

```ruby
class TestToolWithProgressableAndCancellable < ModelContextProtocol::Server::Tool
  define do
    name "test_tool_with_progressable_and_cancellable"
    description "A test tool that demonstrates combined progressable and cancellable functionality"

    input_schema do
      {
        type: "object",
        properties: {
          max_duration: {
            type: "number",
            description: "Expected maximum duration in seconds"
          },
          work_steps: {
            type: "number",
            description: "Number of work steps to perform"
          }
        },
        required: ["max_duration"]
      }
    end
  end

  def call
    max_duration = arguments[:max_duration] || 10
    work_steps = arguments[:work_steps] || 10
    logger.info("Starting progressable call with max_duration=#{max_duration}, work_steps=#{work_steps}")

    result = progressable(max_duration:, message: "Processing #{work_steps} items") do
      cancellable do
        processed_items = []

        work_steps.times do |i|
          sleep(max_duration / work_steps.to_f)
          processed_items << "item_#{i + 1}"
        end

        processed_items
      end
    end

    response = text_content(text: "Successfully processed #{result.length} items: #{result.join(", ")}")

    respond_with content: response
  end
end
```

---

## Completions

The `ModelContextProtocol::Server::Completion` base class allows subclasses to define a completion that the MCP client can use to obtain hints or suggestions for arguments to prompts and resources.

Implement the `call` method to build your completion logic using the provided argument name and value. Completions are simpler than other server features - they don't use a `define` block and only provide filtered suggestion lists.

### Completion Methods

Completions only implement the `call` method to provide completion logic.

| Method | Context | Description |
|--------|---------|-------------|
| `call` | Instance method | Main method to implement completion logic and build response |
| `respond_with` | Within `call` | Return properly formatted completion response (e.g., `respond_with values:`) |

### Available Instance Variables

Completions receive the argument name and current value being completed.

| Variable | Context | Description |
|----------|---------|-------------|
| `argument_name` | Within `call` | String name of the argument being completed |
| `argument_value` | Within `call` | Current partial value being typed by the user |

### Examples

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

---

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
