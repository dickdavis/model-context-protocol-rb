require_relative "matchers/be_valid_mcp_class"

# Tool response matchers
require_relative "matchers/be_valid_mcp_tool_response"
require_relative "matchers/have_structured_content"
require_relative "matchers/have_text_content"
require_relative "matchers/have_image_content"
require_relative "matchers/have_audio_content"
require_relative "matchers/have_embedded_resource_content"
require_relative "matchers/have_resource_link_content"
require_relative "matchers/be_mcp_error_response"

# Prompt response matchers
require_relative "matchers/be_valid_mcp_prompt_response"
require_relative "matchers/have_message_with_role"
require_relative "matchers/have_message_count"

# Resource response matchers
require_relative "matchers/be_valid_mcp_resource_response"
require_relative "matchers/have_resource_text"
require_relative "matchers/have_resource_blob"
require_relative "matchers/have_resource_mime_type"
require_relative "matchers/have_resource_annotations"

module ModelContextProtocol
  module RSpec
    module Matchers
      # Include all matchers when this module is included
    end
  end
end
