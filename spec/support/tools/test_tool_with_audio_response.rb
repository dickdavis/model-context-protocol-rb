class TestToolWithAudioResponse < ModelContextProtocol::Server::Tool
  define do
    name "text-to-speech"
    description "Converts text to speech audio"
    input_schema do
      {
        type: "object",
        properties: {
          text: {
            type: "string",
            description: "Text to convert to speech"
          },
          format: {
            type: "string",
            description: "Audio format (mp3, wav, ogg)"
          }
        },
        required: ["text", "format"]
      }
    end
  end

  def call
    # Map format to mime type
    mime_type = case arguments[:format].downcase
    when "mp3"
      "audio/mpeg"
    when "wav"
      "audio/wav"
    when "ogg"
      "audio/ogg"
    else
      "audio/mpeg"
    end

    # In a real implementation, we would generate actual audio
    # This is a small valid base64 encoded string (represents "test")
    data = "dGVzdA=="
    audio_content = audio_content(data:, mime_type:)
    respond_with content: audio_content
  end
end
