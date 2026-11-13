module MCPC
  module JsonRpc
    # Assigns request ids, matches responses to waiting callers, and hands
    # inbound requests and notifications to whoever registered for them.
    class Router
      NO_HEADERS = Transport::Headers.new

      def initialize(@transport : Transport)
        @pending = PendingCalls.new
        @last_id = Atomic(Int64).new(0)
        @request_handler = ->(request : Request) { refuse(request) }
        @notification_handler = ->(_notification : Notification) { }
        @close_handler = ->(_error : Exception?) { }
        listen_to_transport
      end

      # Sends a request and returns the `Call` to await its response on.
      def open(method : String, params : Params? = nil, headers = NO_HEADERS) : Call
        open(method, params, headers) { }
      end

      # As above; the block receives the `Call` before anything is sent, so
      # the caller can prepare for messages that may precede the response.
      def open(method : String, params : Params?, headers = NO_HEADERS, & : Call ->) : Call
        id = @last_id.add(1) + 1
        call = Call.new(id, @pending.register(id))
        yield call
        deliver_or_forget(Request.new(id, method, wrap(params)), headers)
        call
      end

      def notify(method : String, params : Params? = nil, headers = NO_HEADERS) : Nil
        @transport.send(Notification.new(method, wrap(params)), headers)
      end

      # Answers a request the server sent.
      def respond(id : Id, result : JSON::Any, headers = NO_HEADERS) : Nil
        @transport.send(Response.success(id, result), headers)
      end

      # Refuses a request the server sent.
      def reject(id : Id, code : Int32, message : String, headers = NO_HEADERS) : Nil
        @transport.send(Response.failure(id, code, message), headers)
      end

      # Ends the wait on *id* with *error*.
      def fail(id : Id, error : Exception) : Nil
        @pending.settle(id, error)
      end

      # Stops expecting a response to *id*; a late one is ignored.
      def forget(id : Id) : Nil
        @pending.forget(id)
      end

      def on_request(&@request_handler : Request ->) : Nil
      end

      def on_notification(&@notification_handler : Notification ->) : Nil
      end

      # The block receives the error that ended the connection, or nil for an orderly end.
      def on_close(&@close_handler : Exception? ->) : Nil
      end

      private def listen_to_transport
        @transport.on_message { |message| route(message) }
        @transport.on_failure { |id, error| fail(id, error) }
        @transport.on_close do |error|
          @pending.settle_all(ConnectionClosedError.new(error.try(&.message) || "connection closed"))
          @close_handler.call(error)
        end
      end

      private def route(message : Request)
        @request_handler.call(message)
      end

      private def route(message : Notification)
        @notification_handler.call(message)
      end

      private def route(message : Response)
        id = message.id
        return Log.debug { "response without an id ignored" } unless id
        settled = @pending.settle(id, outcome_of(message))
        Log.debug { "response to unknown request #{id} ignored" } unless settled
      end

      private def outcome_of(response : Response) : PendingCalls::Outcome
        if error = response.error
          RpcError.new(error.code, error.message, error.data)
        else
          response.result || ProtocolError.new("response carries neither result nor error")
        end
      end

      private def refuse(request : Request)
        reject(request.id, Protocol::ErrorCode::METHOD_NOT_FOUND, "Method not found: #{request.method}")
      end

      private def deliver_or_forget(request : Request, headers)
        @transport.send(request, headers)
      rescue error
        forget(request.id)
        raise error
      end

      private def wrap(params : Params?) : JSON::Any?
        params.try { |object| JSON::Any.new(object) }
      end
    end
  end
end
