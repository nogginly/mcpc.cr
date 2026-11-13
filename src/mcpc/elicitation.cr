module MCPC
  # A server's question for the user, in form mode: `message` says what is
  # wanted and `requested_schema` describes the fields of the answer.
  # Both are written by the server; treat them as untrusted.
  struct ElicitationRequest
    include JSON::Serializable

    getter message : String
    getter mode : String = "form"
    @[JSON::Field(key: "requestedSchema")]
    getter requested_schema : JSON::Any?

    # The user answered; *content* holds the fields the schema asked for.
    def accept(content) : ElicitationResponse
      ElicitationResponse.new("accept", Json.any(content))
    end

    # The user said no.
    def decline : ElicitationResponse
      ElicitationResponse.new("decline")
    end

    # The user dismissed the question without choosing.
    def cancel : ElicitationResponse
      ElicitationResponse.new("cancel")
    end
  end

  # The user's answer to an `ElicitationRequest`. Build one with
  # `ElicitationRequest#accept`, `#decline` or `#cancel`.
  struct ElicitationResponse
    include JSON::Serializable

    getter action : String
    getter content : JSON::Any?

    def initialize(@action : String, @content : JSON::Any? = nil)
    end
  end
end
