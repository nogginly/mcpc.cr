# An in-memory transport wired to a `FakeServer`.
class FakeTransport < MCPC::Transport
  getter sent = [] of {MCPC::JSONRPC::Message, Headers}
  getter aborted = [] of MCPC::JSONRPC::Id
  getter? opened = false
  getter? closed = false

  # When true, `abort` claims to have cancelled the request, as HTTP does.
  property? aborts_requests = false
  property? uses_headers = false

  def initialize(@server : FakeServer)
    @server.connect { |message| deliver(message) }
  end

  def open : Nil
    @opened = true
  end

  def send(message : MCPC::JSONRPC::Message, headers : Headers) : Nil
    raise MCPC::ConnectionClosedError.new if closed?
    sent << {message, headers}
    spawn { @server.receive(message) }
  end

  def abort(id : MCPC::JSONRPC::Id) : Bool
    aborted << id
    aborts_requests?
  end

  def close : Nil
    @closed = true
    closed
  end

  # Simulates the connection dropping.
  def drop(reason = "pipe broke") : Nil
    @closed = true
    closed(IO::Error.new(reason))
  end

  def headers_for(method : String) : Headers
    sent.compact_map { |message, headers| headers if message.as?(MCPC::JSONRPC::Request).try(&.method) == method }.last
  end
end

def connected_client(server : FakeServer, config = fast_config, & : MCPC::Client, FakeTransport ->)
  transport = FakeTransport.new(server)
  client = MCPC::Client.new(transport, config)
  yield client, transport
ensure
  client.try(&.close)
end
