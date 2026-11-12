module Mcpc
  # Delivers events to the application's handler, in order, on a fiber of
  # its own. The handler may therefore call back into the client.
  class EventDispatcher
    QUEUE_SIZE = 1024

    def initialize
      @queue = Channel(Event).new(QUEUE_SIZE)
      @handler = ->(_event : Event) { }
      spawn(name: "mcpc-events") { deliver_queued }
    end

    def on_event(&@handler : Event ->) : Nil
    end

    def emit(event : Event) : Nil
      @queue.send(event)
    rescue Channel::ClosedError
    end

    # Stops delivery once the events already queued have been handled.
    def close : Nil
      @queue.close
    end

    private def deliver_queued
      while event = @queue.receive?
        handle(event)
      end
    end

    private def handle(event : Event)
      @handler.call(event)
    rescue error
      Log.error(exception: error) { "event handler raised" }
    end
  end
end
