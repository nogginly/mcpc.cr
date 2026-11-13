require "../spec_helper"

private def detect(server : FakeServer, config = fast_config) : {MCPC::Era::Strategy, FakeTransport}
  transport = FakeTransport.new(server)
  transport.uses_headers = true
  context = MCPC::Era::Context.new(MCPC::JSONRPC::Router.new(transport), transport, config,
    MCPC::EventDispatcher.new, MCPC::ClientInput.new)
  {MCPC::Era::Detector.new(context).detect, transport}
end

describe MCPC::Era::Detector do
  it "probes with a self-describing server/discover request" do
    server = FakeServer.modern
    _, transport = detect(server)

    probe = server.requests.first
    probe.method.should eq("server/discover")
    meta = params_of(probe)["_meta"]
    meta["io.modelcontextprotocol/protocolVersion"].should eq("2026-07-28")
    meta["io.modelcontextprotocol/clientCapabilities"].should eq(JSON.parse("{}"))
    meta["io.modelcontextprotocol/clientInfo"]["name"].should eq("mcpc")
    transport.headers_for("server/discover").should eq(
      {"MCP-Protocol-Version" => "2026-07-28", "Mcp-Method" => "server/discover"})
  end

  it "chooses the stateless era when discovery succeeds" do
    strategy, _ = detect(FakeServer.modern)

    strategy.should be_a(MCPC::Era::Stateless)
    strategy.server.protocol_version.should eq("2026-07-28")
    strategy.server.stateless?.should be_true
    strategy.server.implementation.try(&.name).should eq("fake-modern")
    strategy.server.capabilities.tools?.should be_true
  end

  it "sends no initialize to a stateless server" do
    server = FakeServer.modern
    detect(server)
    server.requests.map(&.method).should eq(["server/discover"])
  end

  it "falls back to the handshake when discovery is an unknown method" do
    server = FakeServer.legacy
    strategy, _ = detect(server)

    strategy.should be_a(MCPC::Era::Handshake)
    strategy.server.protocol_version.should eq("2025-11-25")
    server.requests.map(&.method).should eq(["server/discover", "initialize"])
  end

  it "does not key the fallback to one error code" do
    server = FakeServer.legacy
    server.fail_with("server/discover", -32600, "Missing Mcp-Session-Id")
    detect(server)[0].should be_a(MCPC::Era::Handshake)
  end

  it "falls back to the handshake when the probe goes unanswered" do
    server = FakeServer.legacy
    server.on("server/discover") { FakeServer::SILENT }
    strategy, transport = detect(server)

    strategy.should be_a(MCPC::Era::Handshake)
    transport.sent.map(&.[0]).select(MCPC::JSONRPC::Notification).map(&.method).should eq(["notifications/initialized"])
  end

  it "falls back to the handshake when a dual-era server offers only older revisions" do
    server = FakeServer.legacy
    server.fail_with("server/discover", -32022, "Unsupported protocol version",
      {"supported" => ["2025-11-25"], "requested" => "2026-07-28"})
    detect(server)[0].should be_a(MCPC::Era::Handshake)
  end

  it "falls back when discovery succeeds but lists only older revisions" do
    server = FakeServer.modern(versions: ["2025-06-18"])
    server.on("initialize") do
      {"protocolVersion" => "2025-06-18", "capabilities" => {} of String => String,
       "serverInfo" => {"name" => "dual", "version" => "1"}}
    end
    detect(server)[0].server.protocol_version.should eq("2025-06-18")
  end

  it "raises when a modern server shares no revision with the client" do
    server = FakeServer.new
    server.fail_with("server/discover", -32022, "Unsupported protocol version",
      {"supported" => ["2027-01-01"], "requested" => "2026-07-28"})

    expect_raises(MCPC::UnsupportedVersionError, "2027-01-01") { detect(server) }
    server.requests.map(&.method).should_not contain("initialize")
  end

  {-32020 => "header mismatch", -32021 => "missing capability"}.each do |code, fault|
    it "raises rather than falling back on a modern #{fault} error" do
      server = FakeServer.legacy
      server.fail_with("server/discover", code, fault)

      expect_raises(MCPC::RPCError, fault) { detect(server) }
      server.requests.map(&.method).should_not contain("initialize")
    end
  end

  it "raises when a handshake server insists on a revision the client does not speak" do
    expect_raises(MCPC::UnsupportedVersionError, "1999-01-01") { detect(FakeServer.legacy(version: "1999-01-01")) }
  end
end
