module Mcpc
  module Era
    # What the client needs from a protocol era. One instance serves one
    # connection for its whole life.
    abstract class Strategy
      getter server : ServerInfo

      def initialize(@context : Context, @server : ServerInfo)
        @context.router.on_notification { |notification| handle_notification(notification) }
        @context.router.on_request { |request| handle_request(request) }
      end

      # Sends a request the way this era requires and returns its final result.
      abstract def request(method : String, params : Params, options : RequestOptions) : JSON::Any

      # Starts change notifications for *filter*.
      abstract def subscribe(filter : SubscriptionFilter) : Subscription

      # Tells the server to stop working on request *id*.
      protected abstract def cancel_on_server(id : JsonRpc::Id, reason : String?) : Nil

      # Returns the tools from a `tools/list` page that this era can call.
      def admit(tools : Array(Tool)) : Array(Tool)
        tools
      end

      protected def handle_notification(notification : JsonRpc::Notification) : Nil
        NotificationEvents.translate(notification).try { |event| @context.events.emit(event) }
      end

      protected def handle_request(request : JsonRpc::Request) : Nil
        @context.router.reject(request.id, Protocol::ErrorCode::METHOD_NOT_FOUND, "Method not found: #{request.method}")
      end

      # Sends one request and waits for its response. A request that times
      # out or is cancelled is also cancelled on the server.
      protected def exchange(method : String, params : Params, headers : Transport::Headers,
                             options = RequestOptions.new) : JSON::Any
        call = @context.router.open(method, params, headers)
        begin
          call.await(options.timeout || @context.config.request_timeout, options.cancellation)
        rescue error : TimeoutError | CancelledError
          abandon(call.id, error.message)
          raise error
        end
      end

      protected def abandon(id : JsonRpc::Id, reason : String?) : Nil
        @context.router.forget(id)
        cancel_on_server(id, reason)
      rescue error : TransportError
        Log.debug { "could not cancel request #{id}: #{error.message}" }
      end

      protected def cancelled_params(id : JsonRpc::Id, reason : String?) : Params
        params = Params{"requestId" => Json.any(id)}
        reason.try { |text| params["reason"] = JSON::Any.new(text) }
        params
      end
    end
  end
end
