require "http/client"

module Mcpc
  # Interprets one HTTP response to a POSTed JSON-RPC request.
  class Transport::HttpReply
    AUTH_STATUSES = {401, 403}

    def initialize(@response : HTTP::Client::Response, @session_active : Bool)
    end

    # Yields every JSON-RPC message in the response, whether it came as a
    # single JSON body or as an event stream.
    #
    # Raises `RpcError` when a refusal carries a JSON-RPC error,
    # `SessionExpiredError` for a 404 during a session, `HttpError` otherwise.
    def each_message(& : JsonRpc::Message ->) : Nil
      raise refusal unless @response.success?
      case @response.content_type
      when "text/event-stream"
        Transport::SseReader.new(@response.body_io).each_message { |data| yield JsonRpc.parse(data) }
      when "application/json"
        yield JsonRpc.parse(@response.body_io.gets_to_end)
      end
    end

    # Raises unless the server accepted a message that expects no reply.
    def expect_accepted : Nil
      raise refusal unless @response.success?
    end

    private def refusal : Exception
      status = @response.status_code
      body = @response.body_io.gets_to_end
      return SessionExpiredError.new(status, body) if status == 404 && @session_active
      return HttpError.new(status, body) if AUTH_STATUSES.includes?(status)
      rpc_error(body) || HttpError.new(status, body)
    end

    private def rpc_error(body : String) : RpcError?
      message = JsonRpc.parse(body)
      error = message.as?(JsonRpc::Response).try(&.error) || return
      RpcError.new(error.code, error.message, error.data)
    rescue JsonRpc::InvalidMessage | JSON::SerializableError
      nil
    end
  end
end
