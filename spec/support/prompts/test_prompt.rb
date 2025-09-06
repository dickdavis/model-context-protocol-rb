class TestPrompt < ModelContextProtocol::Server::Prompt
  ToneCompletion = ModelContextProtocol::Server::Completion.define do
    hints = ["whiny", "angry", "callous", "desperate", "nervous", "sneaky"]
    values = hints.grep(/#{argument_value}/)

    respond_with values:
  end

  with_metadata do
    name "brainstorm_excuses"
    title "Brainstorm Excuses"
    description "A prompt for brainstorming excuses to get out of something"

    argument do
      name "undesirable_activity"
      description "The thing to get out of"
      required true
    end

    argument do
      name "tone"
      description "The general tone to be used in the generated excuses"
      required false
      completion ToneCompletion
    end
  end

  def call
    logger.info("Brainstorming excuses...")
    messages = [
      {
        role: "user",
        content: {
          type: "text",
          text: "My wife wants me to: #{arguments[:undesirable_activity]}... Can you believe it?"
        }
      },
      {
        role: "assistant",
        content: {
          type: "text",
          text: "Oh, that's just downright awful. What are you going to do?"
        }
      },
      {
        role: "user",
        content: {
          type: "text",
          text: "Well, I'd like to get out of it, but I'm going to need your help."
        }
      },
      {
        role: "assistant",
        content: {
          type: "text",
          text: "Anything for you."
        }
      },
      {
        role: "user",
        content: {
          type: "text",
          text: "Can you generate some excuses for me?" + (arguments[:tone] ? "Make them as #{arguments[:tone]} as possible." : "")
        }
      }
    ]

    respond_with messages: messages
  end
end
