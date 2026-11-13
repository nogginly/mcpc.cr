require "http/client"
require "uri"

module MCPC
  # Talks to a server's single MCP endpoint, one HTTP POST per message.
  #
  # A session id issued by a handshake-era server is remembered and sent on
  # every later request; `close` ends that session.
  class Transport::StreamableHttp < Transport
    SESSION_HEADER = "Mcp-Session-Id"
    ACCEPT_BOTH    = "application/json, text/event-stream"
    ACCEPT_STREAM  = "text/event-stream"

    # *headers* accompany every request; use them for credentials.
    def initialize(url : String, @headers : Headers = Headers.new)
      @uri = URI.parse(url)
      @session_id = nil.as(String?)
      @streams = {} of JsonRpc::Id => HTTP::Client
      @aborted = Set(JsonRpc::Id).new
      @server_stream = nil.as(HTTP::Client?)
      @lock = Mutex.new
      @closed = false
    end

    def open : Nil
    end

    def uses_headers? : Bool
      true
    end

    # A request is answered on its own fiber, so the caller never waits on
    # the network. Other messages are posted before this method returns.
    def send(message : JsonRpc::Message, headers : Headers) : Nil
      case message
      in JsonRpc::Request
        spawn(name: "mcpc-http-request") { exchange(message, headers) }
      in JsonRpc::Notification, JsonRpc::Response
        post_one_way(message, headers)
      end
    end

    # Closes the response stream of request *id*, which a 2026-07-28 server
    # treats as cancellation.
    def abort(id : JsonRpc::Id) : Bool
      connection = @lock.synchronize do
        @streams.delete(id).tap { |found| @aborted << id if found }
      end
      connection.try(&.close)
      !connection.nil?
    end

    # Opens the GET stream on which handshake-era servers send messages
    # unrelated to any request. Servers that offer none are left alone.
    def listen(headers : Headers) : Nil
      spawn(name: "mcpc-http-listener") { read_server_stream(headers) }
    end

    def close : Nil
      @closed = true
      connections = @lock.synchronize do
        (@streams.values + [@server_stream].compact).tap { @streams.clear }
      end
      connections.each(&.close)
      end_session
      closed
    end

    private def exchange(request : JsonRpc::Request, headers : Headers)
      connection = track(request.id)
      answered = false
      connection.post(@uri.request_target, request_headers(headers, ACCEPT_BOTH), request.to_json) do |response|
        remember_session(response)
        HttpReply.new(response, session_active?).each_message do |message|
          answered ||= answers?(message, request)
          deliver(message)
        end
      end
      fail(request.id, ConnectionClosedError.new("stream ended before the response")) unless answered
    rescue error
      fail(request.id, as_transport_error(error)) unless aborted?(request.id)
    ensure
      untrack(request.id)
    end

    private def post_one_way(message, headers : Headers)
      connection = HTTP::Client.new(@uri)
      connection.post(@uri.request_target, request_headers(headers, ACCEPT_BOTH), message.to_json) do |response|
        HttpReply.new(response, session_active?).expect_accepted
      end
    rescue error : IO::Error | Socket::Error
      raise as_transport_error(error)
    ensure
      connection.try(&.close)
    end

    private def read_server_stream(headers : Headers)
      return if @closed
      connection = HTTP::Client.new(@uri)
      @server_stream = connection
      connection.get(@uri.request_target, request_headers(headers, ACCEPT_STREAM)) do |response|
        next unless response.success? && response.content_type == ACCEPT_STREAM
        SseReader.new(response.body_io).each_message { |data| deliver(JsonRpc.parse(data)) }
      end
    rescue error : IO::Error | Socket::Error | JsonRpc::InvalidMessage
      Log.debug { "server stream ended: #{error.message}" }
    end

    private def end_session
      session_id = @session_id || return
      @session_id = nil
      headers = request_headers(Headers{SESSION_HEADER => session_id}, ACCEPT_BOTH)
      HTTP::Client.new(@uri).delete(@uri.request_target, headers, &.status_code)
    rescue error : IO::Error | Socket::Error
      Log.debug { "could not end the session: #{error.message}" }
    end

    private def request_headers(headers : Headers, accept : String) : HTTP::Headers
      result = HTTP::Headers{"Content-Type" => "application/json", "Accept" => accept}
      @session_id.try { |id| result[SESSION_HEADER] = id }
      @headers.each { |name, value| result[name] = value }
      headers.each { |name, value| result[name] = value }
      result
    end

    private def remember_session(response : HTTP::Client::Response)
      response.headers[SESSION_HEADER]?.try { |id| @session_id = id }
    end

    private def session_active? : Bool
      !@session_id.nil?
    end

    private def answers?(message : JsonRpc::Message, request : JsonRpc::Request) : Bool
      message.is_a?(JsonRpc::Response) && message.id == request.id
    end

    private def track(id : JsonRpc::Id) : HTTP::Client
      HTTP::Client.new(@uri).tap { |connection| @lock.synchronize { @streams[id] = connection } }
    end

    private def untrack(id : JsonRpc::Id)
      @lock.synchronize { @streams.delete(id) }.try(&.close)
    end

    private def aborted?(id : JsonRpc::Id) : Bool
      @lock.synchronize { @aborted.delete(id) }
    end

    private def as_transport_error(error : Exception) : Exception
      error.is_a?(Error) ? error : TransportError.new(error.message)
    end
  end
end
