require "../spec_helper"

private def router_with(server : FakeServer) : {MCPC::JSONRPC::Router, FakeTransport}
  transport = FakeTransport.new(server)
  {MCPC::JSONRPC::Router.new(transport), transport}
end

describe MCPC::JSONRPC::Router do
  it "returns the result of the response with the matching id" do
    server = FakeServer.new
    server.on("echo", &.params)
    router, _ = router_with(server)

    router.open("echo", MCPC::Params{"n" => JSON::Any.new(1_i64)}).await.should eq(JSON.parse(%({"n":1})))
  end

  it "gives each request its own id" do
    server = FakeServer.new
    server.on("echo") { {"ok" => true} }
    router, _ = router_with(server)

    first = router.open("echo")
    second = router.open("echo")
    first.id.should_not eq(second.id)
  end

  it "matches responses that arrive out of order" do
    server = FakeServer.new
    release_slow = Channel(Nil).new
    server.on("slow") { release_slow.receive; {"name" => "slow"} }
    server.on("fast") { {"name" => "fast"} }
    router, _ = router_with(server)

    slow = router.open("slow")
    router.open("fast").await["name"].should eq("fast")
    release_slow.send(nil)
    slow.await["name"].should eq("slow")
  end

  it "raises RPCError for an error response" do
    server = FakeServer.new
    server.fail_with("fail", -32602, "Unknown tool", {"tool" => "x"})
    router, _ = router_with(server)

    error = expect_raises(MCPC::RPCError, "Unknown tool") { router.open("fail").await }
    error.code.should eq(-32602)
    error.data.should eq(JSON.parse(%({"tool":"x"})))
  end

  it "hands server notifications to the notification handler" do
    server = FakeServer.new
    router, _ = router_with(server)
    seen = [] of String
    router.on_notification { |notification| seen << notification.method }

    server.push("notifications/tools/list_changed")
    seen.should eq(["notifications/tools/list_changed"])
  end

  it "hands server requests to the request handler, not to a waiting caller" do
    server = FakeServer.new
    release = Channel(Nil).new
    server.on("work") { release.receive; {"done" => true} }
    router, _ = router_with(server)
    asked = [] of MCPC::JSONRPC::Id
    router.on_request { |request| asked << request.id }

    call = router.open("work")
    server.ask(call.id, "elicitation/create", {"message" => "?"})
    release.send(nil)

    call.await["done"].should be_true
    asked.should eq([call.id])
  end

  it "refuses server requests nobody handles" do
    server = FakeServer.new
    router_with(server)

    server.ask("srv-1", "roots/list", {} of String => String)
    wait_until { !server.responses.empty? }
    server.responses.first.id.should eq("srv-1")
    server.responses.first.error.try(&.code).should eq(-32601)
  end

  it "answers a server request with the same id type" do
    server = FakeServer.new
    router, _ = router_with(server)

    router.respond("srv-9", JSON.parse(%({"action":"accept"})))
    wait_until { !server.responses.empty? }
    server.responses.first.id.should eq("srv-9")
  end

  it "ignores a response nobody waits for" do
    server = FakeServer.new
    server.on("echo") { {"ok" => true} }
    router, _ = router_with(server)

    call = router.open("echo")
    router.forget(call.id)
    router.open("echo").await["ok"].should be_true
  end

  it "times out when no response arrives" do
    server = FakeServer.new
    server.on("hang") { FakeServer::SILENT }
    router, _ = router_with(server)

    expect_raises(MCPC::TimeoutError) { router.open("hang").await(20.milliseconds) }
  end

  it "stops waiting once cancelled, giving the reason" do
    server = FakeServer.new
    server.on("hang") { FakeServer::SILENT }
    router, _ = router_with(server)
    cancellation = MCPC::Cancellation.new

    spawn { cancellation.cancel("user pressed stop") }
    expect_raises(MCPC::CancelledError, "user pressed stop") do
      router.open("hang").await(cancellation: cancellation)
    end
  end

  it "fails every waiting request when the connection closes" do
    server = FakeServer.new
    server.on("hang") { FakeServer::SILENT }
    router, transport = router_with(server)
    closed_with = [] of String?
    router.on_close { |error| closed_with << error.try(&.message) }

    call = router.open("hang")
    transport.drop("pipe broke")

    expect_raises(MCPC::ConnectionClosedError, "pipe broke") { call.await }
    closed_with.should eq(["pipe broke"])
  end

  it "raises at once when the message cannot be sent" do
    router, transport = router_with(FakeServer.new)
    transport.close

    expect_raises(MCPC::ConnectionClosedError) { router.open("echo") }
  end

  it "lets the caller prepare before the request is sent" do
    server = FakeServer.new
    server.on("echo") { {"ok" => true} }
    router, transport = router_with(server)

    sent_when_prepared = -1
    router.open("echo", nil) { sent_when_prepared = transport.sent.size }
    sent_when_prepared.should eq(0)
  end
end
