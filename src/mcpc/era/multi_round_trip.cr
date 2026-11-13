module MCPC
  module Era
    # Repeats a request for as long as the server answers "input required",
    # attaching the input it asked for each time.
    class MultiRoundTrip
      def initialize(@input : ClientInput, @max_rounds : Int32)
      end

      # Yields the params for each round and returns the first complete result.
      # Raises `InputRequiredError` when the server still wants input after
      # the allowed number of rounds.
      def run(params : Params, & : Params -> JSON::Any) : JSON::Any
        round_params = params
        @max_rounds.times do
          result = yield round_params
          return result unless result["resultType"]? == "input_required"
          round_params = params.merge(retry_fields(result))
        end
        raise InputRequiredError.new("server still requires input after #{@max_rounds} rounds")
      end

      # Steps: answer each input request under the key the server chose,
      # and echo the server's opaque request state untouched.
      private def retry_fields(result : JSON::Any) : Params
        fields = Params.new
        result["inputRequests"]?.try { |requests| fields["inputResponses"] = responses_to(requests) }
        result["requestState"]?.try { |state| fields["requestState"] = state }
        fields
      end

      private def responses_to(requests : JSON::Any) : JSON::Any
        answers = requests.as_h.transform_values do |request|
          @input.answer(request["method"].as_s, request["params"]?)
        end
        JSON::Any.new(answers)
      end
    end
  end
end
