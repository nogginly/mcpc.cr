module Mcpc
  module Era
    # One open `subscriptions/listen` request.
    class ListenStream
      getter call : JsonRpc::Call
      getter? acknowledged = false

      def initialize(@call : JsonRpc::Call)
        @opening = Channel(SubscriptionFilter | Exception).new(1)
      end

      # Records the server's acknowledgement and the filter it agreed to.
      def acknowledge(filter : SubscriptionFilter) : Nil
        return if acknowledged?
        @acknowledged = true
        @opening.send(filter)
      end

      # Records that the stream ended before the server acknowledged it.
      def reject(error : Exception) : Nil
        @opening.send(error) unless acknowledged?
      end

      # Blocks until the server acknowledges and returns the agreed filter.
      # Raises what ended the stream if it ended first.
      def await_acknowledgement(timeout : Time::Span) : SubscriptionFilter
        select
        when opening = @opening.receive
          raise opening if opening.is_a?(Exception)
          opening
        when timeout(timeout)
          raise TimeoutError.new("subscription was not acknowledged in time")
        end
      end
    end
  end
end
