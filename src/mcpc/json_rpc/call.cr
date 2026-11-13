module MCPC
  module JsonRpc
    # One request that has been sent and not yet answered.
    class Call
      getter id : Id

      def initialize(@id : Id, @outcome : Channel(PendingCalls::Outcome))
      end

      # Blocks until the response arrives and returns its `result`.
      #
      # Raises `RpcError` for an error response, `TimeoutError` after *timeout*,
      # `CancelledError` once *cancellation* is cancelled, and whatever error
      # ended the connection.
      def await(timeout : Time::Span? = nil, cancellation : Cancellation? = nil) : JSON::Any
        outcome = wait(timeout, cancellation || Cancellation.new)
        raise outcome if outcome.is_a?(Exception)
        outcome
      end

      private def wait(timeout : Nil, cancellation : Cancellation) : PendingCalls::Outcome
        select
        when outcome = @outcome.receive
          outcome
        when cancellation.signal.receive?
          CancelledError.new(cancellation.reason)
        end
      end

      private def wait(timeout : Time::Span, cancellation : Cancellation) : PendingCalls::Outcome
        select
        when outcome = @outcome.receive
          outcome
        when cancellation.signal.receive?
          CancelledError.new(cancellation.reason)
        when timeout(timeout)
          TimeoutError.new
        end
      end
    end
  end
end
