require "./spec_helper"

private def http_client(server : FakeServer, & : MCPC::Client, HTTPFakeServer ->)
  HTTPFakeServer.open(server) do |http|
    client = MCPC::Client.http(http.url, {"Authorization" => "Bearer secret"}, fast_config)
    begin
      yield client, http
    ensure
      client.close
    end
  end
end

describe "MCPC::Client over Streamable HTTP" do
  describe "with a stateless server" do
    it "discovers, then sends self-describing requests with routing headers" do
      server = FakeServer.modern
      server.on("tools/call") { text_result("5").merge({"resultType" => "complete"}) }
      http_client(server) do |client, http|
        client.connect.stateless?.should be_true
        client.call_tool("add", {"a" => 2, "b" => 3}).text.should eq("5")

        headers = http.headers_for("tools/call")
        headers["MCP-Protocol-Version"].should eq("2026-07-28")
        headers["Mcp-Method"].should eq("tools/call")
        headers["Mcp-Name"].should eq("add")
        headers["Authorization"].should eq("Bearer secret")
        headers["Mcp-Session-Id"]?.should be_nil
        http.http_methods.uniq.should eq(["POST"])
      end
    end

    it "reads progress from the event stream of the request it belongs to" do
      server = FakeServer.modern
      server.on("tools/call") do |_request, exchange|
        exchange.notify("notifications/progress", {"progressToken" => "job-1", "progress" => 1, "total" => 2})
        text_result("done")
      end
      http_client(server) do |client, http|
        http.streaming = true
        log = EventLog.new(client)
        client.connect
        client.call_tool("slow", options: MCPC::RequestOptions.new(progress_token: "job-1")).text.should eq("done")
        log.await(MCPC::Event::Progress).total.should eq(2.0)
      end
    end

    it "stays stateless and raises when the server reports a modern error with HTTP 400" do
      server = FakeServer.modern
      server.fail_with("tools/call", -32602, "Unknown tool: nope")
      http_client(server) do |client, http|
        http.error_statuses[-32602] = 400
        client.connect
        expect_raises(MCPC::RPCError, "Unknown tool: nope") { client.call_tool("nope") }
        server.requests_for("initialize").should be_empty
      end
    end

    it "cancels a timed-out request by closing its stream, sending no notification" do
      server = FakeServer.modern
      hold = Channel(Bool).new
      server.on("tools/call") { hold.receive?; FakeServer::SILENT }
      http_client(server) do |client, http|
        http.streaming = true
        client.connect
        expect_raises(MCPC::TimeoutError) do
          client.call_tool("slow", options: MCPC::RequestOptions.new(timeout: 50.milliseconds))
        end
        server.notifications.should be_empty
        hold.close
      end
    end

    it "keeps a listen stream open and ends it by closing the stream" do
      server = FakeServer.modern
      hold = Channel(Bool).new
      server.on("subscriptions/listen") do |request, exchange|
        meta = {"io.modelcontextprotocol/subscriptionId" => request.id}
        exchange.notify("notifications/subscriptions/acknowledged", {"_meta" => meta, "notifications" => {"toolsListChanged" => true}})
        exchange.notify("notifications/tools/list_changed", {"_meta" => meta})
        hold.receive?
        FakeServer::SILENT
      end
      http_client(server) do |client, http|
        http.streaming = true
        log = EventLog.new(client)
        client.connect
        subscription = client.subscribe(MCPC::SubscriptionFilter.new(tools: true))

        log.await(MCPC::Event::ToolsChanged)
        subscription.close
        sleep 20.milliseconds
        log.of(MCPC::Event::SubscriptionClosed).should be_empty
        server.notifications.should be_empty
        hold.close
      end
    end
  end

  describe "with a handshake-era server" do
    it "falls back on a plain HTTP 400 and carries the session id from then on" do
      server = FakeServer.legacy
      server.fail_with("server/discover", -32600, "Bad Request: Mcp-Session-Id header is required")
      server.on("tools/list") { {"tools" => [{"name" => "echo", "inputSchema" => {"type" => "object"}}]} }
      http_client(server) do |client, http|
        http.session_id = "session-1"
        http.error_statuses[-32600] = 400
        client.connect.protocol_version.should eq("2025-11-25")
        client.list_tools.map(&.name).should eq(["echo"])

        headers = http.headers_for("tools/list")
        headers["Mcp-Session-Id"].should eq("session-1")
        headers["MCP-Protocol-Version"].should eq("2025-11-25")
        headers["Mcp-Method"]?.should be_nil
        server.notifications.map(&.method).should eq(["notifications/initialized"])
      end
    end

    it "ends the session when closed" do
      server = FakeServer.legacy
      HTTPFakeServer.open(server) do |http|
        http.session_id = "session-1"
        client = MCPC::Client.http(http.url, config: fast_config)
        client.connect
        client.close
        http.http_methods.should contain("DELETE")
      end
    end

    it "receives unrequested notifications on the GET stream" do
      server = FakeServer.legacy
      http_client(server) do |client, http|
        http.server_stream = true
        log = EventLog.new(client)
        client.connect
        wait_until { http.http_methods.includes?("GET") }

        server.push("notifications/tools/list_changed")
        log.await(MCPC::Event::ToolsChanged)
      end
    end

    it "answers elicitation that arrives on a tool call's event stream by POSTing the response" do
      server = FakeServer.legacy
      server.on("tools/call") do |_request, exchange|
        exchange.ask("ask-1", "elicitation/create", {"message" => "Name?", "requestedSchema" => {"type" => "object", "properties" => {"name" => {"type" => "string"}}}})
        wait_until { !server.responses.empty? }
        text_result("Hello #{result_of(server.responses.first)["content"]["name"]}")
      end
      http_client(server) do |client, http|
        http.streaming = true
        client.on_elicitation(&.accept({"name" => "Ada"}))
        client.connect
        client.call_tool("greet").text.should eq("Hello Ada")
      end
    end

    it "tells the server about a cancelled request with a notification" do
      server = FakeServer.legacy
      hold = Channel(Bool).new
      server.on("tools/call") { hold.receive?; FakeServer::SILENT }
      http_client(server) do |client, http|
        http.streaming = true
        client.connect
        expect_raises(MCPC::TimeoutError) do
          client.call_tool("slow", options: MCPC::RequestOptions.new(timeout: 50.milliseconds))
        end
        wait_until { server.notifications.map(&.method).includes?("notifications/cancelled") }
        hold.close
      end
    end
  end

  it "does not fall back when the server refuses authorization" do
    server = FakeServer.legacy
    server.fail_with("server/discover", -32600, "Unauthorized")
    http_client(server) do |client, http|
      http.error_statuses[-32600] = 401
      expect_raises(MCPC::HTTPError, "HTTP 401") { client.connect }
      server.requests_for("initialize").should be_empty
    end
  end
end
