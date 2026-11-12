module Mcpc
  module Era
    # Answers the requests a handshake-era server sends to the client.
    class ServerRequests
      def initialize(@context : Context, @headers : Transport::Headers)
      end

      # Replies on a fiber of its own, because answering may wait on a person.
      def answer(request : JsonRpc::Request) : Nil
        spawn(name: "mcpc-server-request") { reply(request) }
      end

      private def reply(request : JsonRpc::Request)
        @context.router.respond(request.id, result_for(request), @headers)
      rescue error : InputRequiredError
        refuse(request, Protocol::ErrorCode::METHOD_NOT_FOUND, error)
      rescue error : ProtocolError
        refuse(request, Protocol::ErrorCode::INVALID_PARAMS, error)
      rescue error : TransportError
        Log.debug { "could not answer #{request.method}: #{error.message}" }
      rescue error
        refuse(request, Protocol::ErrorCode::INTERNAL_ERROR, error)
      end

      private def result_for(request : JsonRpc::Request) : JSON::Any
        return JSON::Any.new(Params.new) if request.method == "ping"
        @context.input.answer(request.method, request.params)
      end

      private def refuse(request : JsonRpc::Request, code : Int32, cause : Exception)
        @context.router.reject(request.id, code, cause.message || cause.class.name, @headers)
      rescue error : TransportError
        Log.debug { "could not refuse #{request.method}: #{error.message}" }
      end
    end
  end
end
