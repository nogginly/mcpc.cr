module MCPC
  # Runs the server as a subprocess and exchanges newline-delimited JSON
  # over its standard input and output.
  class Transport::Stdio < Transport
    # *stderr* is where the server's free-form logging goes. *shutdown_grace*
    # is how long `close` waits at each step before forcing the server out.
    def initialize(@command : String, @args = [] of String, @env : Process::Env = nil,
                   @stderr : Process::Stdio = Process::Redirect::Inherit,
                   @shutdown_grace : Time::Span = 2.seconds)
      @write_lock = Mutex.new
      @process = nil.as(Process?)
    end

    def open : Nil
      process = Process.new(@command, @args, env: @env, input: :pipe, output: :pipe, error: @stderr)
      @process = process
      spawn(name: "mcpc-stdio-reader") { read_messages(process.output) }
    rescue error : File::Error | IO::Error
      raise TransportError.new("cannot start #{@command}: #{error.message}")
    end

    def send(message : JSONRPC::Message, headers : Headers) : Nil
      input = running_process.input
      @write_lock.synchronize do
        input.puts(message.to_json)
        input.flush
      end
    rescue error : IO::Error
      raise ConnectionClosedError.new("server is not reading: #{error.message}")
    end

    # Steps: close the server's stdin, wait for it to exit, ask it to
    # terminate, then kill it.
    def close : Nil
      process = @process || return
      @process = nil
      process.input.close
      exited = exit_signal(process)
      return if exits_within_grace?(exited)
      process.terminate
      return if exits_within_grace?(exited)
      process.terminate(graceful: false)
    end

    private def running_process : Process
      @process || raise ConnectionClosedError.new("transport is not open")
    end

    private def read_messages(output : IO)
      output.each_line { |line| deliver_line(line) }
      closed
    rescue error : IO::Error
      closed(error)
    end

    private def deliver_line(line : String)
      return if line.blank?
      deliver(JSONRPC.parse(line))
    rescue error : JSONRPC::InvalidMessage | JSON::SerializableError
      Log.warn { "ignored a line from the server that is not JSON-RPC: #{error.message}" }
    end

    private def exit_signal(process : Process) : Channel(Nil)
      exited = Channel(Nil).new
      spawn do
        process.wait
        exited.close
      end
      exited
    end

    private def exits_within_grace?(exited : Channel(Nil)) : Bool
      select
      when exited.receive?
        true
      when timeout(@shutdown_grace)
        false
      end
    end
  end
end
