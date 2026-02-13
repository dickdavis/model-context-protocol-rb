require "model_context_protocol"
require_relative "rspec/matchers"
require_relative "rspec/helpers"
require_relative "rspec/shared_contexts"

module ModelContextProtocol
  module RSpec
    # Convenience method to configure RSpec with MCP matchers and helpers.
    #
    # @example
    #   # In spec_helper.rb
    #   require "model_context_protocol/rspec"
    #   ModelContextProtocol::RSpec.configure!
    #
    # @return [void]
    def self.configure!
      ::RSpec.configure do |config|
        config.include ModelContextProtocol::RSpec::Matchers
        config.include ModelContextProtocol::RSpec::Helpers, type: :mcp
        config.include ModelContextProtocol::RSpec::Helpers, file_path: %r{spec/mcp/}
      end
    end
  end
end
