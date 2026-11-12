module Mcpc
  # Answers what a server asks of the client side. Only form-mode
  # elicitation is supported, and only once the application has
  # registered a handler for it.
  class ClientInput
    ELICITATION = "elicitation/create"

    alias ElicitationHandler = ElicitationRequest -> ElicitationResponse

    property elicitation_handler : ElicitationHandler?

    # The client capabilities to declare to servers.
    def capabilities : JSON::Any
      return JSON::Any.new(Params.new) unless elicitation_handler
      Json.any({"elicitation" => {"form" => Params.new}})
    end

    # Returns the result for a server's *method* request.
    # Raises `InputRequiredError` when nothing here can answer it.
    def answer(method : String, params : JSON::Any?) : JSON::Any
      handler = elicitation_handler
      raise InputRequiredError.new("no handler answers #{method}") unless handler && method == ELICITATION
      request = ElicitationRequest.from_json(params.to_json)
      raise InputRequiredError.new("#{request.mode} elicitation is not supported") unless request.mode == "form"
      Json.any(handler.call(request))
    rescue error : JSON::SerializableError
      raise ProtocolError.new("malformed #{method}: #{error.message}")
    end
  end
end
