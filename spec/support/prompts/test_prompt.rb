class TestPrompt < ModelContextProtocol::Server::Prompt
  define do
    # The name of the prompt for programmatic use
    name "brainstorm_excuses"
    # The human-readable prompt name for display in UI
    title "Brainstorm Excuses"
    # A short description of what the tool does
    description "A prompt for brainstorming excuses to get out of something"

    # Define arguments to be used with your prompt
    argument do
      # The name of the argument
      name "tone"
      # A short description of the argument
      description "The general tone to be used in the generated excuses"
      # If the argument is required
      required false
      # Available hints for completions
      completion ["whiny", "angry", "callous", "desperate", "nervous", "sneaky"]
    end

    argument do
      name "undesirable_activity"
      description "The thing to get out of"
      required true
    end
  end

  # You can optionally define a custom completion for an argument and pass it to completions.
  # ToneCompletion = ModelContextProtocol::Server::Completion.define do
  #   hints = ["whiny", "angry", "callous", "desperate", "nervous", "sneaky"]
  #   values = hints.grep(/#{argument_value}/)
  #   respond_with values:
  # end
  #   ...
  # define do
  #   argument do
  #     name "tone"
  #     description "The general tone to be used in the generated excuses"
  #     required false
  #     completion ToneCompletion
  #   end
  # end

  # The call method is invoked by the MCP Server to generate a response to resource/read requests
  def call
    # You can use the client_logger
    client_logger.info("Brainstorming excuses...")

    # Server logging for debugging and monitoring (not sent to client)
    server_logger.debug("Prompt called with arguments: #{arguments}")
    server_logger.info("Generating excuse brainstorming prompt")

    # Build an array of user and assistant messages
    messages = message_history do
      # Create a message with the user role
      user_message do
        # Use any type of content block in a message (text, image, audio, embedded_resource, or resource_link)
        text_content(text: "My wife wants me to: #{arguments[:undesirable_activity]}... Can you believe it?")
      end

      # You can also create messages with the assistant role
      assistant_message do
        text_content(text: "Oh, that's just downright awful. How can I help?")
      end

      user_message do
        # Reference any inputs from the client by accessing the appropriate key in the arguments hash
        text_content(text: "Can you generate some excuses for me?" + (arguments[:tone] ? " Make them as #{arguments[:tone]} as possible." : ""))
      end
    end

    user_id = context[:user_id]
    if user_id
      server_logger.info("User #{user_id} is generating excuses")
    end

    # Respond with the messages
    respond_with messages:
  end
end
