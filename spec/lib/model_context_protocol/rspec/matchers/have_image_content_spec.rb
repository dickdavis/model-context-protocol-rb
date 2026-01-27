require "spec_helper"
require "model_context_protocol/rspec"

RSpec.describe ModelContextProtocol::RSpec::Matchers::HaveImageContent do
  include ModelContextProtocol::RSpec::Matchers
  include McpHelpers

  describe "#matches?" do
    context "with a valid image content response" do
      it "matches when image is present" do
        response = call_mcp_tool(TestToolWithImageResponse, {chart_type: "bar", format: "png"})
        expect(response).to have_image_content
      end

      it "matches with mime type constraint" do
        response = call_mcp_tool(TestToolWithImageResponse, {chart_type: "bar", format: "png"})
        expect(response).to have_image_content(mime_type: "image/png")
      end

      it "matches with svg mime type" do
        response = call_mcp_tool(TestToolWithImageResponse, {chart_type: "bar", format: "svg"})
        expect(response).to have_image_content(mime_type: "image/svg+xml")
      end
    end

    context "with mixed content response" do
      it "matches image in mixed content" do
        response = call_mcp_tool(TestToolWithMixedContentResponse, {zip: "12345"})
        expect(response).to have_image_content
      end

      it "matches image with mime type in mixed content" do
        response = call_mcp_tool(TestToolWithMixedContentResponse, {zip: "12345"})
        expect(response).to have_image_content(mime_type: "image/png")
      end
    end

    context "with a Hash response" do
      it "matches when image is present" do
        response = {content: [{type: "image", data: "base64data", mimeType: "image/jpeg"}], isError: false}
        expect(response).to have_image_content
      end

      it "matches with string keys" do
        response = {"content" => [{"type" => "image", "data" => "base64", "mimeType" => "image/png"}], "isError" => false}
        expect(response).to have_image_content
      end
    end

    context "with non-matching responses" do
      it "fails when no image content present" do
        response = {content: [{type: "text", text: "Hello"}], isError: false}
        expect(response).not_to have_image_content
      end

      it "fails when mime type does not match" do
        response = call_mcp_tool(TestToolWithImageResponse, {chart_type: "bar", format: "png"})
        expect(response).not_to have_image_content(mime_type: "image/jpeg")
      end
    end

    context "with invalid responses" do
      it "fails for nil response" do
        expect(nil).not_to have_image_content
      end

      it "fails for response without content" do
        response = {isError: false}
        expect(response).not_to have_image_content
      end
    end
  end

  describe "#failure_message" do
    it "provides helpful message when no image content found" do
      response = {content: [{type: "text", text: "Hello"}], isError: false}
      matcher = have_image_content
      matcher.matches?(response)

      expect(matcher.failure_message).to include("no image content found")
    end

    it "provides helpful message when mime type does not match" do
      response = {content: [{type: "image", data: "base64", mimeType: "image/png"}], isError: false}
      matcher = have_image_content(mime_type: "image/jpeg")
      matcher.matches?(response)

      expect(matcher.failure_message).to include("no image content with mime type 'image/jpeg'")
      expect(matcher.failure_message).to include("image/png")
    end
  end

  describe "#description" do
    it "returns a description without constraints" do
      matcher = have_image_content
      expect(matcher.description).to eq("have image content")
    end

    it "returns a description with mime type constraint" do
      matcher = have_image_content(mime_type: "image/png")
      expect(matcher.description).to eq("have image content with mime type 'image/png'")
    end
  end
end
