require "model_context_protocol"
require_relative "rspec/matchers"

module ModelContextProtocol
  module RSpec
    # Convenience method to configure RSpec with MCP matchers.
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
      end
    end
  end
end
