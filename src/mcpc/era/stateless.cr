module MCPC
  module Era
    # The 2026-07-28 revision: no handshake, every request describes itself,
    # and the server asks for input by having the request retried.
    class Stateless < Strategy
      LISTEN       = "subscriptions/listen"
      ACKNOWLEDGED = "notifications/subscriptions/acknowledged"
      CANCELLED    = "notifications/cancelled"

      def initialize(context : Context, server : ServerInfo)
        super
        @meta = RequestMeta.new(server.protocol_version, context.config, context.input.capabilities)
        @headers = RoutingHeaders.new(server.protocol_version)
        @rounds = MultiRoundTrip.new(context.input, context.config.max_input_rounds)
        @streams = {} of JSONRPC::Id => ListenStream
      end

      def request(method : String, params : Params, options : RequestOptions) : JSON::Any
        @rounds.run(params) do |round_params|
          exchange(method, @meta.apply(round_params, options), @headers.for(method, round_params), options)
        end
      end

      # Opens a listen stream and waits for the server to acknowledge it.
      def subscribe(filter : SubscriptionFilter) : Subscription
        stream = open_stream(filter)
        spawn(name: "mcpc-subscription") { watch(stream) }
        agreed = stream.await_acknowledgement(@context.config.request_timeout)
        Subscription.new(agreed) { end_stream(stream) }
      rescue error : TimeoutError
        stream.try { |opened| end_stream(opened) }
        raise error
      end

      # Over HTTP, a tool with invalid `x-mcp-header` annotations must be left out.
      def admit(tools : Array(Tool)) : Array(Tool)
        return tools unless @context.transport.uses_headers?
        tools.select { |tool| @headers.learn(tool) }
      end

      protected def handle_notification(notification : JSONRPC::Notification) : Nil
        case notification.method
        when ACKNOWLEDGED then acknowledge(notification)
        when CANCELLED    then end_by_server(notification)
        else                   super
        end
      end

      protected def cancel_on_server(id : JSONRPC::Id, reason : String?) : Nil
        return if @context.transport.abort(id)
        @context.router.notify(CANCELLED, cancelled_params(id, reason))
      end

      private def open_stream(filter : SubscriptionFilter) : ListenStream
        params = Params{"notifications" => JSONValue.any(filter)}
        call = @context.router.open(LISTEN, @meta.apply(params), @headers.for(LISTEN, params)) do |opened|
          @streams[opened.id] = ListenStream.new(opened)
        end
        @streams[call.id]
      end

      # Steps: wait for the listen request to end, then report why, unless
      # the application ended it or it never got going.
      private def watch(stream : ListenStream)
        stream.call.await
        stream_ended(stream, nil)
      rescue CancelledError
        @streams.delete(stream.call.id)
      rescue error : Error
        stream_ended(stream, error)
      end

      private def stream_ended(stream : ListenStream, error : Error?)
        @streams.delete(stream.call.id)
        if stream.acknowledged?
          @context.events.emit(Event::SubscriptionClosed.new(error.try(&.message)))
        else
          stream.reject(error || ProtocolError.new("subscription closed before it was acknowledged"))
        end
      end

      private def end_stream(stream : ListenStream)
        cancel_on_server(stream.call.id, nil)
        @context.router.fail(stream.call.id, CancelledError.new)
      end

      private def acknowledge(notification : JSONRPC::Notification)
        params = notification.params || return
        id = subscription_id(params) || return
        filter = SubscriptionFilter.from_json(params["notifications"].to_json)
        @streams[id]?.try(&.acknowledge(filter))
      rescue error : JSON::SerializableError | KeyError
        Log.warn { "ignored malformed #{ACKNOWLEDGED}: #{error.message}" }
      end

      private def end_by_server(notification : JSONRPC::Notification)
        params = notification.params || return
        id = request_id(params["requestId"]?) || return
        reason = params["reason"]?.try(&.as_s?) || "cancelled by the server"
        @context.router.fail(id, Error.new(reason))
      end

      private def subscription_id(params : JSON::Any) : JSONRPC::Id?
        request_id(params.dig?("_meta", "io.modelcontextprotocol/subscriptionId"))
      end

      private def request_id(value : JSON::Any?) : JSONRPC::Id?
        value.try { |id| id.as_i64? || id.as_s? }
      end
    end
  end
end
