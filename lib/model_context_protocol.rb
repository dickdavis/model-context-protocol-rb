require "addressable/template"

Dir[File.join(__dir__, "model_context_protocol/", "**", "*.rb")].sort.each { |file| require_relative file }

##
# Top-level namespace
module ModelContextProtocol
end
