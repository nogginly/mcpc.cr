require "http/server"

# Serves a `FakeServer` over Streamable HTTP on a local port.
class HttpFakeServer
  record Received, method : String, headers : HTTP::Headers, message : MCPC::JsonRpc::Message?

  getter received = [] of Received
  getter url : String

  # Reply to requests with an event stream rather than a JSON body.
  property? streaming = false
  # Issue this session id at `initialize` and demand it afterwards.
  property session_id : String? = nil
  # The HTTP status to send with each JSON-RPC error code; 200 when absent.
  property error_statuses = {} of Int32 => Int32
  # Offer a GET stream for messages outside any request.
  property? server_stream = false

  def initialize(@server : FakeServer)
    @pushes = Channel(MCPC::JsonRpc::Message).new(16)
    @server.connect { |message| @pushes.send(message) }
    @http = HTTP::Server.new { |context| handle(context) }
    address = @http.bind_tcp("127.0.0.1", 0)
    @url = "http://127.0.0.1:#{address.port}/mcp"
    spawn { @http.listen }
    Fiber.yield
  end

  def self.open(server : FakeServer, & : HttpFakeServer ->)
    http = new(server)
    yield http
  ensure
    http.try(&.close)
  end

  def close : Nil
    @pushes.close
    @http.close
  end

  def headers_for(method : String) : HTTP::Headers
    entry = received.reverse_each.find { |candidate| candidate.message.as?(MCPC::JsonRpc::Request).try(&.method) == method }
    entry.try(&.headers) || raise "no #{method} request was received"
  end

  def http_methods : Array(String)
    received.map(&.method)
  end

  private def handle(context : HTTP::Server::Context)
    case context.request.method
    when "POST"   then post(context)
    when "GET"    then stream_pushes(context)
    when "DELETE" then record(context, nil)
    else               context.response.status_code = 405
    end
  end

  private def post(context : HTTP::Server::Context)
    message = MCPC::JsonRpc.parse(context.request.body.try(&.gets_to_end) || "")
    record(context, message)
    return context.response.status_code = 404 if session_missing?(context, message)
    case message
    in MCPC::JsonRpc::Request
      streaming? ? reply_with_stream(context, message) : reply_with_json(context, message)
    in MCPC::JsonRpc::Notification, MCPC::JsonRpc::Response
      @server.receive(message)
      context.response.status_code = 202
    end
  end

  private def reply_with_json(context, request : MCPC::JsonRpc::Request)
    emitted = [] of MCPC::JsonRpc::Message
    @server.receive(request, ->(message : MCPC::JsonRpc::Message) { emitted << message; nil })
    reply = emitted.last?
    context.response.status_code = status_for(reply)
    issue_session(context, request)
    return unless reply
    context.response.content_type = "application/json"
    context.response.print(reply.to_json)
  end

  private def reply_with_stream(context, request : MCPC::JsonRpc::Request)
    issue_session(context, request)
    start_stream(context)
    @server.receive(request, ->(message : MCPC::JsonRpc::Message) { write_event(context, message) })
  end

  private def stream_pushes(context)
    record(context, nil)
    return context.response.status_code = 405 unless server_stream?
    start_stream(context)
    while message = @pushes.receive?
      write_event(context, message)
    end
  end

  private def start_stream(context)
    context.response.content_type = "text/event-stream"
    context.response.print(": keep-alive\n\n")
    context.response.flush
  end

  private def write_event(context, message : MCPC::JsonRpc::Message) : Nil
    context.response.print("event: message\ndata: #{message.to_json}\n\n")
    context.response.flush
  rescue IO::Error
  end

  private def status_for(reply : MCPC::JsonRpc::Message?) : Int32
    error = reply.as?(MCPC::JsonRpc::Response).try(&.error) || return 200
    error_statuses[error.code]? || 200
  end

  private def issue_session(context, request : MCPC::JsonRpc::Request)
    return unless request.method == "initialize"
    session_id.try { |id| context.response.headers["Mcp-Session-Id"] = id }
  end

  private def session_missing?(context, message) : Bool
    expected = session_id || return false
    return false if message.as?(MCPC::JsonRpc::Request).try(&.method).in?("initialize", "server/discover")
    context.request.headers["Mcp-Session-Id"]? != expected
  end

  private def record(context, message : MCPC::JsonRpc::Message?)
    received << Received.new(context.request.method, context.request.headers, message)
  end
end
