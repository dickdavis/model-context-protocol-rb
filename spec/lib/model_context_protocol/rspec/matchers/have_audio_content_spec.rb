require "spec_helper"
require "model_context_protocol/rspec"

RSpec.describe ModelContextProtocol::RSpec::Matchers::HaveAudioContent do
  include ModelContextProtocol::RSpec::Matchers
  include McpHelpers

  describe "#matches?" do
    context "with a valid audio content response" do
      it "matches when audio is present" do
        response = call_mcp_tool(TestToolWithAudioResponse, {text: "Hello", format: "mp3"})
        expect(response).to have_audio_content
      end

      it "matches with mime type constraint" do
        response = call_mcp_tool(TestToolWithAudioResponse, {text: "Hello", format: "mp3"})
        expect(response).to have_audio_content(mime_type: "audio/mpeg")
      end

      it "matches with wav mime type" do
        response = call_mcp_tool(TestToolWithAudioResponse, {text: "Hello", format: "wav"})
        expect(response).to have_audio_content(mime_type: "audio/wav")
      end
    end

    context "with a Hash response" do
      it "matches when audio is present" do
        response = {content: [{type: "audio", data: "base64data", mimeType: "audio/mp3"}], isError: false}
        expect(response).to have_audio_content
      end

      it "matches with string keys" do
        response = {"content" => [{"type" => "audio", "data" => "base64", "mimeType" => "audio/wav"}], "isError" => false}
        expect(response).to have_audio_content
      end
    end

    context "with non-matching responses" do
      it "fails when no audio content present" do
        response = {content: [{type: "text", text: "Hello"}], isError: false}
        expect(response).not_to have_audio_content
      end

      it "fails when mime type does not match" do
        response = {content: [{type: "audio", data: "base64", mimeType: "audio/mp3"}], isError: false}
        expect(response).not_to have_audio_content(mime_type: "audio/wav")
      end
    end

    context "with invalid responses" do
      it "fails for nil response" do
        expect(nil).not_to have_audio_content
      end

      it "fails for response without content" do
        response = {isError: false}
        expect(response).not_to have_audio_content
      end
    end
  end

  describe "#failure_message" do
    it "provides helpful message when no audio content found" do
      response = {content: [{type: "text", text: "Hello"}], isError: false}
      matcher = have_audio_content
      matcher.matches?(response)

      expect(matcher.failure_message).to include("no audio content found")
    end

    it "provides helpful message when mime type does not match" do
      response = {content: [{type: "audio", data: "base64", mimeType: "audio/mp3"}], isError: false}
      matcher = have_audio_content(mime_type: "audio/wav")
      matcher.matches?(response)

      expect(matcher.failure_message).to include("no audio content with mime type 'audio/wav'")
      expect(matcher.failure_message).to include("audio/mp3")
    end
  end

  describe "#description" do
    it "returns a description without constraints" do
      matcher = have_audio_content
      expect(matcher.description).to eq("have audio content")
    end

    it "returns a description with mime type constraint" do
      matcher = have_audio_content(mime_type: "audio/mp3")
      expect(matcher.description).to eq("have audio content with mime type 'audio/mp3'")
    end
  end
end
