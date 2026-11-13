module MCPC
  # Lets an application abandon a request that another fiber is waiting on.
  #
  # ```
  # cancellation = MCPC::Cancellation.new
  # spawn { client.call_tool("slow", options: MCPC::RequestOptions.new(cancellation: cancellation)) }
  # cancellation.cancel("user pressed stop")
  # ```
  #
  # The waiting call raises `CancelledError`.
  class Cancellation
    getter reason : String?

    # Closed once cancelled, which wakes every fiber receiving from it.
    # :nodoc:
    getter signal = Channel(Nil).new

    def cancel(@reason : String? = nil) : Nil
      @signal.close
    end

    def cancelled? : Bool
      @signal.closed?
    end
  end
end
