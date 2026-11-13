module MCPC
  # Carries JSON-RPC messages to and from one server.
  #
  # Subclass it to add a transport. A subclass calls `deliver` for each
  # inbound message, `fail` when a request can never be answered, and
  # `closed` once when the connection ends.
  abstract class Transport
    # Routing metadata sent beside a message. Transports without a header
    # layer, such as stdio, ignore it.
    alias Headers = Hash(String, String)

    @message_handler : JsonRpc::Message -> = ->(_message : JsonRpc::Message) { }
    @failure_handler : JsonRpc::Id, Exception -> = ->(_id : JsonRpc::Id, _error : Exception) { }
    @close_handler : Exception? -> = ->(_error : Exception?) { }

    # Makes the transport ready to send.
    abstract def open : Nil

    # Sends one message. A response to a request arrives later through `on_message`.
    abstract def send(message : JsonRpc::Message, headers : Headers) : Nil

    # Ends the connection and releases its resources.
    abstract def close : Nil

    # Whether `Headers` passed to `send` reach the server.
    def uses_headers? : Bool
      false
    end

    # Cancels request *id* by transport means alone. Returns false when the
    # transport has none, in which case the caller must tell the server itself.
    def abort(id : JsonRpc::Id) : Bool
      false
    end

    # Starts receiving messages the server sends outside any request, where
    # the transport needs a separate channel for them.
    def listen(headers : Headers) : Nil
    end

    def on_message(&@message_handler : JsonRpc::Message ->) : Nil
    end

    def on_failure(&@failure_handler : JsonRpc::Id, Exception ->) : Nil
    end

    def on_close(&@close_handler : Exception? ->) : Nil
    end

    protected def deliver(message : JsonRpc::Message) : Nil
      @message_handler.call(message)
    end

    protected def fail(id : JsonRpc::Id, error : Exception) : Nil
      @failure_handler.call(id, error)
    end

    protected def closed(error : Exception? = nil) : Nil
      @close_handler.call(error)
    end
  end
end
