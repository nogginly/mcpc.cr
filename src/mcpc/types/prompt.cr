module Mcpc
  struct PromptArgument
    include JSON::Serializable

    getter name : String
    getter title : String?
    getter description : String?
    getter? required : Bool = false
  end

  # A message template the server offers for a user to pick.
  struct Prompt
    include JSON::Serializable

    getter name : String
    getter title : String?
    getter description : String?
    getter arguments : Array(PromptArgument) = [] of PromptArgument
  end

  # `role` is "user" or "assistant".
  struct PromptMessage
    include JSON::Serializable

    getter role : String
    getter content : Content
  end

  # A prompt filled in with arguments, ready to hand to a model.
  struct PromptResult
    include JSON::Serializable

    getter description : String?
    getter messages : Array(PromptMessage)
  end
end
