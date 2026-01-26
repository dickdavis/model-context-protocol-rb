# frozen_string_literal: true

require_relative "lib/model_context_protocol/version"

Gem::Specification.new do |spec|
  spec.name = "model-context-protocol-rb"
  spec.version = ModelContextProtocol::VERSION
  spec.authors = ["Dick Davis"]
  spec.email = ["webmaster@dick.codes"]

  spec.summary = "An implementation of the Model Context Protocol (MCP) in Ruby."
  spec.homepage = "https://github.com/dickdavis/model-context-protocol-rb"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.4"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "https://github.com/dickdavis/model-context-protocol-rb/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ spec/ .git Gemfile])
    end
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "json-schema", "~> 5.1"
  spec.add_dependency "addressable", "~> 2.8"
  spec.add_dependency "redis", "~> 5.0"
  spec.add_dependency "connection_pool", "~> 3.0"
  spec.add_dependency "concurrent-ruby", "~> 1.3"
end
