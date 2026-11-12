module Mcpc
  module JsonRpc
    # The requests still waiting for a response, keyed by id.
    class PendingCalls
      alias Outcome = JSON::Any | Exception

      def initialize
        @waiting = {} of Id => Channel(Outcome)
        @lock = Mutex.new
      end

      # Starts waiting on *id*; the returned channel receives its outcome once.
      def register(id : Id) : Channel(Outcome)
        channel = Channel(Outcome).new(1)
        @lock.synchronize { @waiting[id] = channel }
        channel
      end

      # Hands *outcome* to whoever waits on *id*. Returns false when nobody does.
      def settle(id : Id, outcome : Outcome) : Bool
        channel = @lock.synchronize { @waiting.delete(id) }
        return false unless channel
        channel.send(outcome)
        true
      end

      def settle_all(outcome : Outcome) : Nil
        channels = @lock.synchronize do
          @waiting.values.tap { @waiting.clear }
        end
        channels.each(&.send(outcome))
      end

      def forget(id : Id) : Nil
        @lock.synchronize { @waiting.delete(id) }
      end
    end
  end
end
