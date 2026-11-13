module MCPC
  # Reads a Server-Sent Events stream.
  class Transport::SseReader
    MESSAGE_EVENT = "message"

    def initialize(@io : IO)
    end

    # Yields the data of each `message` event, with multi-line data joined
    # by newlines. Comments and other event types are skipped.
    def each_message(& : String ->) : Nil
      event = MESSAGE_EVENT
      data = [] of String
      @io.each_line do |line|
        if line.empty?
          yield data.join('\n') if event == MESSAGE_EVENT && !data.empty?
          event = MESSAGE_EVENT
          data.clear
        else
          field, _, value = line.partition(':')
          value = value.lchop(' ')
          case field
          when "data"  then data << value
          when "event" then event = value
          end
        end
      end
    end
  end
end
