require "../spec_helper"

private NO_HEADERS = Mcpc::Transport::Headers.new

# Collects what a transport reports, for assertions.
private class Inbox
  getter messages = [] of Mcpc::JsonRpc::Message
  getter failures = [] of {Mcpc::JsonRpc::Id, Exception}

  def initialize(transport : Mcpc::Transport)
    transport.on_message { |message| messages << message }
    transport.on_failure { |id, error| failures << {id, error} }
  end

  def methods : Array(String)
    messages.compact_map(&.as?(Mcpc::JsonRpc::Notification).try(&.method))
  end
end

private def request(id : Int64, method : String, params = nil) : Mcpc::JsonRpc::Request
  Mcpc::JsonRpc::Request.new(id, method, params.try { |value| Mcpc::Json.any(value) })
end

private def with_http(server : FakeServer, headers = NO_HEADERS, & : HttpFakeServer, Mcpc::Transport::StreamableHttp, Inbox ->)
  HttpFakeServer.open(server) do |http|
    transport = Mcpc::Transport::StreamableHttp.new(http.url, headers)
    begin
      yield http, transport, Inbox.new(transport)
    ensure
      transport.close
    end
  end
end

describe Mcpc::Transport::StreamableHttp do
  it "delivers a response sent as a JSON body" do
    server = FakeServer.new
    server.on("tools/list") { {"tools" => [] of String} }
    with_http(server) do |http, transport, inbox|
      transport.send(request(1, "tools/list"), NO_HEADERS)

      wait_until { inbox.messages.size == 1 }
      inbox.messages.first.as(Mcpc::JsonRpc::Response).id.should eq(1_i64)
      http.headers_for("tools/list")["Accept"].should eq("application/json, text/event-stream")
      http.headers_for("tools/list")["Content-Type"].should eq("application/json")
    end
  end

  it "delivers every message of a response sent as an event stream" do
    server = FakeServer.new
    server.on("tools/call") do |_request, exchange|
      exchange.notify("notifications/progress", {"progressToken" => "p", "progress" => 1})
      {"content" => [] of String}
    end
    with_http(server) do |http, transport, inbox|
      http.streaming = true
      transport.send(request(2, "tools/call"), NO_HEADERS)

      wait_until { inbox.messages.size == 2 }
      inbox.methods.should eq(["notifications/progress"])
      inbox.messages.last.as(Mcpc::JsonRpc::Response).id.should eq(2_i64)
      inbox.failures.should be_empty
    end
  end

  it "sends the caller's headers and its own standing headers" do
    server = FakeServer.new
    server.on("tools/list") { {"tools" => [] of String} }
    standing = Mcpc::Transport::Headers{"Authorization" => "Bearer secret"}
    with_http(server, standing) do |http, transport, inbox|
      transport.send(request(1, "tools/list"), Mcpc::Transport::Headers{"Mcp-Method" => "tools/list"})

      wait_until { inbox.messages.size == 1 }
      http.headers_for("tools/list")["Authorization"].should eq("Bearer secret")
      http.headers_for("tools/list")["Mcp-Method"].should eq("tools/list")
    end
  end

  it "remembers the session id and ends the session on close" do
    server = FakeServer.legacy
    server.on("tools/list") { {"tools" => [] of String} }
    HttpFakeServer.open(server) do |http|
      http.session_id = "session-7"
      transport = Mcpc::Transport::StreamableHttp.new(http.url)
      inbox = Inbox.new(transport)

      transport.send(request(1, "initialize"), NO_HEADERS)
      wait_until { inbox.messages.size == 1 }
      http.headers_for("initialize")["Mcp-Session-Id"]?.should be_nil

      transport.send(request(2, "tools/list"), NO_HEADERS)
      wait_until { inbox.messages.size == 2 }
      http.headers_for("tools/list")["Mcp-Session-Id"].should eq("session-7")

      transport.close
      http.http_methods.last.should eq("DELETE")
      http.received.last.headers["Mcp-Session-Id"].should eq("session-7")
    end
  end

  it "does not send DELETE when there was no session" do
    with_http(FakeServer.new) do |http, transport, _inbox|
      transport.close
      http.http_methods.should_not contain("DELETE")
    end
  end

  it "reports an expired session" do
    server = FakeServer.legacy
    HttpFakeServer.open(server) do |http|
      http.session_id = "session-7"
      transport = Mcpc::Transport::StreamableHttp.new(http.url)
      inbox = Inbox.new(transport)
      transport.send(request(1, "initialize"), NO_HEADERS)
      wait_until { inbox.messages.size == 1 }

      http.session_id = "session-8"
      transport.send(request(2, "tools/list"), NO_HEADERS)

      wait_until { inbox.failures.size == 1 }
      inbox.failures.first[0].should eq(2_i64)
      inbox.failures.first[1].should be_a(Mcpc::SessionExpiredError)
    end
  end

  it "reports a JSON-RPC error sent with an HTTP error status as RpcError" do
    server = FakeServer.new
    server.fail_with("tools/call", -32022, "Unsupported protocol version", {"supported" => ["2025-11-25"]})
    with_http(server) do |http, transport, inbox|
      http.error_statuses[-32022] = 400
      transport.send(request(1, "tools/call"), NO_HEADERS)

      wait_until { inbox.failures.size == 1 }
      error = inbox.failures.first[1].as(Mcpc::RpcError)
      error.code.should eq(-32022)
      error.data.should eq(JSON.parse(%({"supported":["2025-11-25"]})))
    end
  end

  it "reports an authorization failure as HttpError, whatever the body" do
    server = FakeServer.new
    server.fail_with("tools/list", -32600, "Unauthorized")
    with_http(server) do |http, transport, inbox|
      http.error_statuses[-32600] = 401
      transport.send(request(1, "tools/list"), NO_HEADERS)

      wait_until { inbox.failures.size == 1 }
      inbox.failures.first[1].as(Mcpc::HttpError).status.should eq(401)
    end
  end

  it "reports a stream that ends without the response" do
    server = FakeServer.new
    server.on("tools/call") { FakeServer::SILENT }
    with_http(server) do |http, transport, inbox|
      http.streaming = true
      transport.send(request(1, "tools/call"), NO_HEADERS)

      wait_until { inbox.failures.size == 1 }
      inbox.failures.first[1].should be_a(Mcpc::ConnectionClosedError)
    end
  end

  it "reports a server that cannot be reached" do
    transport = Mcpc::Transport::StreamableHttp.new("http://127.0.0.1:1/mcp")
    inbox = Inbox.new(transport)
    transport.send(request(1, "tools/list"), NO_HEADERS)

    wait_until { inbox.failures.size == 1 }
    inbox.failures.first[1].should be_a(Mcpc::TransportError)
  end

  it "posts a notification and accepts 202 with no body" do
    server = FakeServer.new
    with_http(server) do |_http, transport, _inbox|
      transport.send(Mcpc::JsonRpc::Notification.new("notifications/initialized"), NO_HEADERS)
      server.notifications.map(&.method).should eq(["notifications/initialized"])
    end
  end

  it "raises when a notification is refused" do
    server = FakeServer.new
    HttpFakeServer.open(server) do |http|
      http.session_id = "required"
      transport = Mcpc::Transport::StreamableHttp.new(http.url)
      expect_raises(Mcpc::HttpError) do
        transport.send(Mcpc::JsonRpc::Notification.new("notifications/initialized"), NO_HEADERS)
      end
    end
  end

  it "aborts a request by closing its stream, without reporting a failure" do
    server = FakeServer.new
    release = Channel(Nil).new
    server.on("tools/call") { release.receive?; FakeServer::SILENT }
    with_http(server) do |http, transport, inbox|
      http.streaming = true
      transport.send(request(1, "tools/call"), NO_HEADERS)
      wait_until { server.requests.size == 1 }
      sleep 20.milliseconds

      transport.abort(1_i64).should be_true
      transport.abort(1_i64).should be_false
      sleep 50.milliseconds
      inbox.failures.should be_empty
      release.close
    end
  end

  it "receives unrequested messages on the GET stream" do
    server = FakeServer.new
    with_http(server) do |http, transport, inbox|
      http.server_stream = true
      transport.listen(Mcpc::Transport::Headers{"MCP-Protocol-Version" => "2025-11-25"})
      wait_until { http.http_methods.includes?("GET") }

      server.push("notifications/tools/list_changed")
      wait_until { inbox.methods == ["notifications/tools/list_changed"] }
      http.received.first.headers["Accept"].should eq("text/event-stream")
      http.received.first.headers["MCP-Protocol-Version"].should eq("2025-11-25")
    end
  end

  it "carries on when the server offers no GET stream" do
    server = FakeServer.new
    server.on("tools/list") { {"tools" => [] of String} }
    with_http(server) do |http, transport, inbox|
      transport.listen(NO_HEADERS)
      wait_until { http.http_methods.includes?("GET") }

      transport.send(request(1, "tools/list"), NO_HEADERS)
      wait_until { inbox.messages.size == 1 }
    end
  end

  it "says that it uses headers" do
    Mcpc::Transport::StreamableHttp.new("http://127.0.0.1:1/mcp").uses_headers?.should be_true
  end
end
