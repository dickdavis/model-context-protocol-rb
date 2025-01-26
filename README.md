# model-context-protocol-rb

An implementation of the [Model Context Protocol (MCP)](https://spec.modelcontextprotocol.io/specification/2024-11-05/) in Ruby.

## Usage

Include `model-context-protocol-rb` in your project.

```ruby
require 'model-context-protocol-rb'
```

# Building an MCP Server

Build a simple MCP server by routing methods to your custom handlers. Then, configure and run the server.

```ruby
server = ModelContextProtocol::Server.new do |config|
  config.name = "My MCP Server"
  config.version = "1.0.0"
  config.enable_log = true
  config.router = ModelContextProtocol::Router.new do
    prompts do
      list Prompt::List, broadcast_changes: true
      get Prompt::Get
    end

    resources do
      list Resource::List, broadcast_changes: true
      read Resource::Read, allow_subscriptions: true
    end

    tools do
      list Tool::List, broadcast_changes: true
      call Tool::Call
    end
  end
end

server.start
```

Messages from the MCP client will be routed to the appropriate custom handler. Your customer handler must respond to `call`; the router will pass the message to the handler as an argument.

Your handler should return a valid JSONRPC 2.0 response.

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
