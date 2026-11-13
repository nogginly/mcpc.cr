require "../spec_helper"

private def sent_notifications(transport : FakeTransport, method : String) : Array(MCPC::JsonRpc::Notification)
  transport.sent.map(&.[0]).select(MCPC::JsonRpc::Notification).select { |notification| notification.method == method }
end

private def meta_of(request : MCPC::JsonRpc::Request) : JSON::Any
  params_of(request)["_meta"]
end

private ELICIT_GUESTS = {"method" => "elicitation/create", "params" => {
  "message" => "How many guests?", "requestedSchema" => {"type" => "object", "properties" => {"guests" => {"type" => "integer"}}},
}}

# A server whose listen stream acknowledges, then stays open until released.
private def listening_server(release : Channel(Bool)) : FakeServer
  FakeServer.modern.tap do |server|
    server.on("subscriptions/listen") do |request, exchange|
      exchange.notify("notifications/subscriptions/acknowledged", {
        "_meta"         => {"io.modelcontextprotocol/subscriptionId" => request.id},
        "notifications" => {"toolsListChanged" => true},
      })
      release.receive? ? {"resultType" => "complete"} : FakeServer::SILENT
    end
  end
end

describe MCPC::Era::Stateless do
  it "makes every request describe itself" do
    server = FakeServer.modern
    server.on("tools/list") { {"tools" => [] of String} }
    connected_client(server) do |client, transport|
      client.connect
      client.list_tools

      meta = meta_of(server.last_request("tools/list"))
      meta["io.modelcontextprotocol/protocolVersion"].should eq("2026-07-28")
      meta["io.modelcontextprotocol/clientCapabilities"].should eq(JSON.parse("{}"))
      meta["io.modelcontextprotocol/clientInfo"]["name"].should eq("mcpc")
      transport.headers_for("tools/list").should eq({"MCP-Protocol-Version" => "2026-07-28", "Mcp-Method" => "tools/list"})
    end
  end

  it "never sends initialize, initialized or ping" do
    server = FakeServer.modern
    server.on("tools/list") { {"tools" => [] of String} }
    connected_client(server) do |client, transport|
      client.connect
      client.list_tools
      server.requests.map(&.method).should eq(["server/discover", "tools/list"])
      transport.sent.map(&.[0]).select(MCPC::JsonRpc::Notification).should be_empty
    end
  end

  it "keeps the caller's progress token beside the required metadata" do
    server = FakeServer.modern
    server.on("tools/call") { text_result("ok") }
    connected_client(server) do |client|
      client.connect
      client.call_tool("slow", options: MCPC::RequestOptions.new(progress_token: "job-1"))

      meta = meta_of(server.last_request("tools/call"))
      meta["progressToken"].should eq("job-1")
      meta["io.modelcontextprotocol/protocolVersion"].should eq("2026-07-28")
    end
  end

  it "asks for the configured log level on every request" do
    server = FakeServer.modern
    server.on("tools/list") { {"tools" => [] of String} }
    connected_client(server, fast_config.tap(&.log_level=("info"))) do |client|
      client.connect
      client.list_tools
      meta_of(server.last_request("tools/list"))["io.modelcontextprotocol/logLevel"].should eq("info")
    end
  end

  it "names the target of a call in the routing headers" do
    server = FakeServer.modern
    server.on("tools/call") { text_result("ok") }
    server.on("resources/read") { {"contents" => [] of String} }
    connected_client(server) do |client, transport|
      client.connect
      client.call_tool("get_weather")
      client.read_resource("file:///todo.md")

      transport.headers_for("tools/call")["Mcp-Name"].should eq("get_weather")
      transport.headers_for("resources/read")["Mcp-Name"].should eq("file:///todo.md")
    end
  end

  describe "over a transport with headers" do
    it "mirrors annotated arguments of listed tools and leaves out invalid tools" do
      server = FakeServer.modern
      server.on("tools/list") do
        {"tools" => [
          {"name" => "execute_sql", "inputSchema" => {"type" => "object", "properties" => {
            "region" => {"type" => "string", "x-mcp-header" => "Region"}, "query" => {"type" => "string"},
          }}},
          {"name" => "broken", "inputSchema" => {"type" => "object", "properties" => {
            "ratio" => {"type" => "number", "x-mcp-header" => "Ratio"},
          }}},
        ]}
      end
      server.on("tools/call") { text_result("ok") }
      connected_client(server) do |client, transport|
        transport.uses_headers = true
        client.connect

        client.list_tools.map(&.name).should eq(["execute_sql"])
        client.call_tool("execute_sql", {"region" => "us-west1", "query" => "SELECT 1"})
        transport.headers_for("tools/call")["Mcp-Param-Region"].should eq("us-west1")
      end
    end
  end

  it "keeps every tool on a transport without headers" do
    server = FakeServer.modern
    server.on("tools/list") do
      {"tools" => [{"name" => "broken", "inputSchema" => {"type" => "object", "properties" => {
        "ratio" => {"type" => "number", "x-mcp-header" => "Ratio"},
      }}}]}
    end
    connected_client(server) do |client|
      client.connect
      client.list_tools.map(&.name).should eq(["broken"])
    end
  end

  describe "when the server requires input" do
    it "declares elicitation, asks the application, and retries with the answer" do
      server = FakeServer.modern
      server.on("tools/call") do |request|
        params = params_of(request)
        if answers = params["inputResponses"]?
          text_result("Booked for #{answers["guests"]["content"]["guests"]}.").merge({"resultType" => "complete"})
        else
          {"resultType" => "input_required", "inputRequests" => {"guests" => ELICIT_GUESTS}, "requestState" => "opaque-state"}
        end
      end
      connected_client(server) do |client|
        client.on_elicitation(&.accept({"guests" => 4}))
        client.connect

        client.call_tool("book_table", {"restaurant" => "Noma"}).text.should eq("Booked for 4.")

        first, second = server.requests_for("tools/call")
        first.id.should_not eq(second.id)
        meta_of(first)["io.modelcontextprotocol/clientCapabilities"].should eq(JSON.parse(%({"elicitation":{"form":{}}})))
        retry = params_of(second)
        retry["arguments"].should eq(JSON.parse(%({"restaurant":"Noma"})))
        retry["requestState"].should eq("opaque-state")
        retry["inputResponses"].should eq(JSON.parse(%({"guests":{"action":"accept","content":{"guests":4}}})))
        meta_of(second)["io.modelcontextprotocol/protocolVersion"].should eq("2026-07-28")
      end
    end

    it "gives up after the configured number of rounds" do
      server = FakeServer.modern
      server.on("tools/call") { {"resultType" => "input_required", "requestState" => "busy"} }
      config = fast_config.tap(&.max_input_rounds=(4))
      connected_client(server, config) do |client|
        client.connect
        expect_raises(MCPC::InputRequiredError) { client.call_tool("busy") }
        server.requests_for("tools/call").size.should eq(4)
      end
    end

    it "raises when the application registered no way to answer" do
      server = FakeServer.modern
      server.on("tools/call") { {"resultType" => "input_required", "inputRequests" => {"guests" => ELICIT_GUESTS}} }
      connected_client(server) do |client|
        client.connect
        expect_raises(MCPC::InputRequiredError, "elicitation/create") { client.call_tool("book_table") }
      end
    end

    it "refuses URL-mode elicitation, which it never declared" do
      server = FakeServer.modern
      server.on("tools/call") do
        {"resultType" => "input_required", "inputRequests" => {
          "login" => {"method" => "elicitation/create", "params" => {"mode" => "url", "message" => "Log in", "url" => "https://example.com"}},
        }}
      end
      connected_client(server) do |client|
        client.on_elicitation(&.accept({} of String => String))
        client.connect
        expect_raises(MCPC::InputRequiredError, "url elicitation") { client.call_tool("login") }
      end
    end
  end

  describe "cancellation" do
    it "sends notifications/cancelled where the transport cannot cancel" do
      server = FakeServer.modern
      server.on("tools/call") { FakeServer::SILENT }
      connected_client(server) do |client, transport|
        client.connect
        expect_raises(MCPC::TimeoutError) do
          client.call_tool("slow", options: MCPC::RequestOptions.new(timeout: 20.milliseconds))
        end

        cancelled = params_of(sent_notifications(transport, "notifications/cancelled").first)
        cancelled["requestId"].should eq(server.last_request("tools/call").id)
      end
    end

    it "leaves cancellation to a transport that can do it, sending nothing" do
      server = FakeServer.modern
      server.on("tools/call") { FakeServer::SILENT }
      connected_client(server) do |client, transport|
        transport.aborts_requests = true
        client.connect
        expect_raises(MCPC::TimeoutError) do
          client.call_tool("slow", options: MCPC::RequestOptions.new(timeout: 20.milliseconds))
        end

        transport.aborted.should eq([server.last_request("tools/call").id])
        sent_notifications(transport, "notifications/cancelled").should be_empty
      end
    end
  end

  describe "subscriptions" do
    it "opens a listen stream and returns the filter the server agreed to" do
      release = Channel(Bool).new
      server = listening_server(release)
      connected_client(server) do |client|
        client.connect
        subscription = client.subscribe(MCPC::SubscriptionFilter.new(tools: true, prompts: true))

        listen = params_of(server.last_request("subscriptions/listen"))
        listen["notifications"]["toolsListChanged"].should be_true
        listen["notifications"]["promptsListChanged"].should be_true
        meta_of(server.last_request("subscriptions/listen"))["io.modelcontextprotocol/protocolVersion"].should eq("2026-07-28")
        subscription.filter.tools?.should be_true
        subscription.filter.prompts?.should be_false
        release.close
      end
    end

    it "delivers notifications of the stream as events" do
      release = Channel(Bool).new
      server = listening_server(release)
      connected_client(server) do |client|
        log = EventLog.new(client)
        client.connect
        client.subscribe(MCPC::SubscriptionFilter.new(tools: true))

        server.push("notifications/tools/list_changed", {"_meta" => {"io.modelcontextprotocol/subscriptionId" => 2}})
        log.await(MCPC::Event::ToolsChanged)
        release.close
      end
    end

    it "cancels the listen request when the application closes the subscription" do
      release = Channel(Bool).new
      server = listening_server(release)
      connected_client(server) do |client, transport|
        log = EventLog.new(client)
        client.connect
        subscription = client.subscribe(MCPC::SubscriptionFilter.new(tools: true))

        subscription.close
        cancelled = params_of(sent_notifications(transport, "notifications/cancelled").first)
        cancelled["requestId"].should eq(server.last_request("subscriptions/listen").id)
        sleep 10.milliseconds
        log.of(MCPC::Event::SubscriptionClosed).should be_empty
        release.close
      end
    end

    it "reports an orderly end by the server" do
      release = Channel(Bool).new(1)
      server = listening_server(release)
      connected_client(server) do |client|
        log = EventLog.new(client)
        client.connect
        client.subscribe(MCPC::SubscriptionFilter.new(tools: true))

        release.send(true)
        log.await(MCPC::Event::SubscriptionClosed).reason.should be_nil
      end
    end

    it "reports a stream the server cancels" do
      release = Channel(Bool).new
      server = listening_server(release)
      connected_client(server) do |client|
        log = EventLog.new(client)
        client.connect
        client.subscribe(MCPC::SubscriptionFilter.new(tools: true))

        server.push("notifications/cancelled", {"requestId" => server.last_request("subscriptions/listen").id, "reason" => "shutting down"})
        log.await(MCPC::Event::SubscriptionClosed).reason.should eq("shutting down")
        release.close
      end
    end

    it "raises the server's refusal instead of waiting for an acknowledgement" do
      server = FakeServer.modern
      server.fail_with("subscriptions/listen", -32601, "Method not found")
      connected_client(server) do |client|
        log = EventLog.new(client)
        client.connect
        expect_raises(MCPC::RpcError, "Method not found") { client.subscribe(MCPC::SubscriptionFilter.new(tools: true)) }
        sleep 10.milliseconds
        log.of(MCPC::Event::SubscriptionClosed).should be_empty
      end
    end

    it "times out and cancels when the server never acknowledges" do
      server = FakeServer.modern
      server.on("subscriptions/listen") { FakeServer::SILENT }
      config = fast_config.tap(&.request_timeout=(30.milliseconds))
      connected_client(server, config) do |client, transport|
        client.connect
        expect_raises(MCPC::TimeoutError) { client.subscribe(MCPC::SubscriptionFilter.new(tools: true)) }
        sent_notifications(transport, "notifications/cancelled").size.should eq(1)
      end
    end
  end
end
