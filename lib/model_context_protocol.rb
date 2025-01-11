# frozen_string_literal: true

Dir[File.join(__dir__, "model_context_protocol/", "**", "*.rb")].sort.each { |file| require_relative file }

##
# Top-level namespace
module ModelContextProtocol
  # TODO: everything
end
