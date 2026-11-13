require "../spec_helper"

private def sent_notifications(transport : FakeTransport, method : String) : Array(MCPC::JsonRpc::Notification)
  transport.sent.map(&.[0]).select(MCPC::JsonRpc::Notification).select { |notification| notification.method == method }
end

describe MCPC::Era::Handshake do
  it "initializes, then announces that it is ready" do
    server = FakeServer.legacy
    connected_client(server) do |client, transport|
      client.connect

      opening = params_of(server.last_request("initialize"))
      opening["protocolVersion"].should eq("2025-11-25")
      opening["capabilities"].should eq(JSON.parse("{}"))
      opening["clientInfo"].should eq(JSON.parse(%({"name":"mcpc","version":"#{MCPC::VERSION}"})))
      sent_notifications(transport, "notifications/initialized").size.should eq(1)
    end
  end

  it "accepts an older revision the server prefers and mirrors it in the version header" do
    server = FakeServer.legacy(version: "2025-06-18")
    server.on("tools/list") { {"tools" => [] of String} }
    connected_client(server) do |client, transport|
      client.connect.protocol_version.should eq("2025-06-18")
      client.list_tools
      transport.headers_for("tools/list").should eq({"MCP-Protocol-Version" => "2025-06-18"})
    end
  end

  it "sends requests without the stateless era's metadata" do
    server = FakeServer.legacy
    server.on("tools/list") { {"tools" => [] of String} }
    connected_client(server) do |client|
      client.connect
      client.list_tools
      server.last_request("tools/list").params.should eq(JSON.parse("{}"))
    end
  end

  it "declares elicitation only when the application can answer" do
    server = FakeServer.legacy
    connected_client(server) do |client|
      client.on_elicitation(&.decline)
      client.connect
      params_of(server.last_request("initialize"))["capabilities"].should eq(JSON.parse(%({"elicitation":{"form":{}}})))
    end
  end

  it "answers a server's elicitation request while the tool call is still open" do
    server = FakeServer.legacy
    server.on("tools/call") do |_request, exchange|
      exchange.ask(100_i64, "elicitation/create", {"message"         => "How many guests?",
                                                   "requestedSchema" => {"type" => "object", "properties" => {"guests" => {"type" => "integer"}}}})
      wait_until { !server.responses.empty? }
      text_result("Booked for #{result_of(server.responses.first)["content"]["guests"]}.")
    end
    connected_client(server) do |client|
      asked = [] of String
      client.on_elicitation do |request|
        asked << request.message
        request.accept({"guests" => 4})
      end
      client.connect

      client.call_tool("book_table").text.should eq("Booked for 4.")
      asked.should eq(["How many guests?"])
      server.responses.first.id.should eq(100_i64)
      server.responses.first.result.should eq(JSON.parse(%({"action":"accept","content":{"guests":4}})))
    end
  end

  it "passes on a declined elicitation" do
    server = FakeServer.legacy
    connected_client(server) do |client|
      client.on_elicitation(&.decline)
      client.connect

      server.ask("q1", "elicitation/create", {"message" => "Sure?", "requestedSchema" => {"type" => "object", "properties" => {} of String => String}})
      wait_until { !server.responses.empty? }
      server.responses.first.result.should eq(JSON.parse(%({"action":"decline"})))
    end
  end

  it "answers ping" do
    server = FakeServer.legacy
    connected_client(server) do |client|
      client.connect
      server.ask("ping-1", "ping", {} of String => String)
      wait_until { !server.responses.empty? }
      server.responses.first.result.should eq(JSON.parse("{}"))
    end
  end

  it "refuses server requests it cannot serve" do
    server = FakeServer.legacy
    connected_client(server) do |client|
      client.connect
      server.ask("s1", "sampling/createMessage", {"messages" => [] of String, "maxTokens" => 10})
      server.ask("e1", "elicitation/create", {"message" => "?"})
      wait_until { server.responses.size == 2 }
      server.responses.map(&.error.try(&.code)).should eq([-32601, -32601])
    end
  end

  it "reports an elicitation handler that raises as an internal error" do
    server = FakeServer.legacy
    connected_client(server) do |client|
      client.on_elicitation { |_request| raise "dialog crashed" }
      client.connect
      server.ask("e1", "elicitation/create", {"message" => "?"})
      wait_until { !server.responses.empty? }
      server.responses.first.error.try(&.code).should eq(-32603)
    end
  end

  it "tells the server when a request is cancelled" do
    server = FakeServer.legacy
    server.on("tools/call") { FakeServer::SILENT }
    connected_client(server) do |client, transport|
      client.connect
      cancellation = MCPC::Cancellation.new
      spawn do
        wait_until { server.requests_for("tools/call").size == 1 }
        cancellation.cancel("user pressed stop")
      end

      expect_raises(MCPC::CancelledError) do
        client.call_tool("slow", options: MCPC::RequestOptions.new(cancellation: cancellation))
      end
      cancelled = params_of(sent_notifications(transport, "notifications/cancelled").first)
      cancelled["requestId"].should eq(server.last_request("tools/call").id)
      cancelled["reason"].should eq("user pressed stop")
    end
  end

  it "tells the server when a request times out" do
    server = FakeServer.legacy
    server.on("tools/call") { FakeServer::SILENT }
    connected_client(server) do |client, transport|
      client.connect
      expect_raises(MCPC::TimeoutError) do
        client.call_tool("slow", options: MCPC::RequestOptions.new(timeout: 20.milliseconds))
      end
      sent_notifications(transport, "notifications/cancelled").size.should eq(1)
    end
  end

  it "asks for the configured log level when the server can log" do
    server = FakeServer.legacy(capabilities: {"logging" => {} of String => String})
    server.on("logging/setLevel") { {} of String => String }
    config = fast_config.tap(&.log_level=("warning"))
    connected_client(server, config) do |client|
      client.connect
      server.last_request("logging/setLevel").params.should eq(JSON.parse(%({"level":"warning"})))
    end
  end

  it "does not ask for a log level the server cannot give" do
    server = FakeServer.legacy
    config = fast_config.tap(&.log_level=("warning"))
    connected_client(server, config) do |client|
      client.connect
      server.requests_for("logging/setLevel").should be_empty
    end
  end

  it "subscribes to resources one request at a time and unsubscribes on close" do
    server = FakeServer.legacy
    server.on("resources/subscribe") { {} of String => String }
    server.on("resources/unsubscribe") { {} of String => String }
    connected_client(server) do |client|
      client.connect
      filter = MCPC::SubscriptionFilter.new(tools: true, resource_uris: ["file:///a", "file:///b"])
      subscription = client.subscribe(filter)

      subscription.filter.should eq(filter)
      server.requests_for("resources/subscribe").map { |request| params_of(request)["uri"].as_s }.should eq(["file:///a", "file:///b"])

      subscription.close
      subscription.close
      server.requests_for("resources/unsubscribe").size.should eq(2)
    end
  end
end
