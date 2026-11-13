require "./spec_helper"

# Behaviour that must be the same whichever era the server belongs to.
private def describe_common_behaviour(era : String, &new_server : -> FakeServer)
  describe "with a #{era} server" do
    it "follows cursors to the end of a list" do
      server = new_server.call
      server.on("tools/list") do |request|
        case request.params.try(&.["cursor"]?).try(&.as_s)
        when nil     then {"tools" => [{"name" => "a", "inputSchema" => {"type" => "object"}}], "nextCursor" => "page2"}
        when "page2" then {"tools" => [{"name" => "b", "inputSchema" => {"type" => "object"}}], "nextCursor" => "page3"}
        else              {"tools" => [{"name" => "c", "inputSchema" => {"type" => "object"}}]}
        end
      end
      connected_client(server) do |client|
        client.connect
        client.list_tools.map(&.name).should eq(["a", "b", "c"])
        server.requests_for("tools/list").size.should eq(3)
      end
    end

    it "stops when a server hands back the same cursor twice" do
      server = new_server.call
      server.on("prompts/list") { {"prompts" => [] of String, "nextCursor" => "stuck"} }
      connected_client(server) do |client|
        client.connect
        expect_raises(MCPC::ProtocolError, "repeated cursor") { client.list_prompts }
      end
    end

    it "calls a tool with its arguments and returns the content" do
      server = new_server.call
      server.on("tools/call") { |request| text_result(params_of(request)["arguments"]["city"].as_s) }
      connected_client(server) do |client|
        client.connect
        result = client.call_tool("get_weather", {"city" => "Oslo"})

        result.text.should eq("Oslo")
        result.error?.should be_false
        params_of(server.last_request("tools/call"))["name"].should eq("get_weather")
      end
    end

    it "omits arguments when a tool is called with none" do
      server = new_server.call
      server.on("tools/call") { text_result("ok") }
      connected_client(server) do |client|
        client.connect
        client.call_tool("ping_db")
        params_of(server.last_request("tools/call")).as_h.has_key?("arguments").should be_false
      end
    end

    it "returns a tool's failure as a result" do
      server = new_server.call
      server.on("tools/call") { text_result("Unknown city: Atlantis", error: true) }
      connected_client(server) do |client|
        client.connect
        result = client.call_tool("get_weather", {"city" => "Atlantis"})
        result.error?.should be_true
        result.text.should eq("Unknown city: Atlantis")
      end
    end

    it "raises RPCError for a protocol failure" do
      server = new_server.call
      server.fail_with("tools/call", -32602, "Unknown tool: nope")
      connected_client(server) do |client|
        client.connect
        expect_raises(MCPC::RPCError, "Unknown tool: nope") { client.call_tool("nope") }.code.should eq(-32602)
      end
    end

    it "raises ProtocolError when a result has the wrong shape" do
      server = new_server.call
      server.on("tools/list") { {"tools" => "many"} }
      connected_client(server) do |client|
        client.connect
        expect_raises(MCPC::ProtocolError, "tools/list") { client.list_tools }
      end
    end

    it "lists and reads resources" do
      server = new_server.call
      server.on("resources/list") { {"resources" => [{"uri" => "file:///todo.md", "name" => "todo"}]} }
      server.on("resources/templates/list") { {"resourceTemplates" => [{"uriTemplate" => "weather://{city}", "name" => "daily"}]} }
      server.on("resources/read") { |request| {"contents" => [{"uri" => params_of(request)["uri"], "text" => "- buy milk"}]} }
      connected_client(server) do |client|
        client.connect
        client.list_resources.map(&.uri).should eq(["file:///todo.md"])
        client.list_resource_templates.map(&.uri_template).should eq(["weather://{city}"])
        client.read_resource("file:///todo.md").first.text.should eq("- buy milk")
      end
    end

    it "lists and gets prompts" do
      server = new_server.call
      server.on("prompts/list") { {"prompts" => [{"name" => "review", "arguments" => [{"name" => "lang", "required" => true}]}]} }
      server.on("prompts/get") do |request|
        lang = params_of(request)["arguments"]["lang"].as_s
        {"messages" => [{"role" => "user", "content" => {"type" => "text", "text" => "Review this #{lang} code"}}]}
      end
      connected_client(server) do |client|
        client.connect
        client.list_prompts.first.arguments.first.required?.should be_true
        message = client.get_prompt("review", {"lang" => "crystal"}).messages.first
        message.content.as(MCPC::TextContent).text.should eq("Review this crystal code")
      end
    end

    it "sends any other request and returns its raw result" do
      server = new_server.call
      server.on("completion/complete") { {"completion" => {"values" => ["crystal"]}} }
      connected_client(server) do |client|
        client.connect
        result = client.request("completion/complete", {"argument" => {"name" => "lang", "value" => "cr"}})
        result["completion"]["values"].should eq(JSON.parse(%(["crystal"])))
      end
    end

    it "reports progress for a request that asked for it" do
      server = new_server.call
      server.on("tools/call") do |request, exchange|
        token = params_of(request)["_meta"]["progressToken"]
        exchange.notify("notifications/progress", {"progressToken" => token, "progress" => 50, "total" => 100, "message" => "halfway"})
        text_result("done")
      end
      connected_client(server) do |client|
        log = EventLog.new(client)
        client.connect
        client.call_tool("slow", options: MCPC::RequestOptions.new(progress_token: "job-1"))

        progress = log.await(MCPC::Event::Progress)
        progress.token.should eq("job-1")
        progress.progress.should eq(50.0)
        progress.total.should eq(100.0)
        progress.message.should eq("halfway")
      end
    end

    it "reports list changes, resource updates and log messages as events, in order" do
      server = new_server.call
      connected_client(server) do |client|
        log = EventLog.new(client)
        client.connect

        server.push("notifications/tools/list_changed")
        server.push("notifications/prompts/list_changed")
        server.push("notifications/resources/list_changed")
        server.push("notifications/resources/updated", {"uri" => "file:///todo.md"})
        server.push("notifications/message", {"level" => "warning", "logger" => "db", "data" => "slow query"})

        wait_until { log.events.size == 5 }
        log.events.map(&.class).should eq([MCPC::Event::ToolsChanged, MCPC::Event::PromptsChanged,
                                           MCPC::Event::ResourcesChanged, MCPC::Event::ResourceUpdated,
                                           MCPC::Event::LogMessage])
        log.of(MCPC::Event::ResourceUpdated).first.uri.should eq("file:///todo.md")
        log.of(MCPC::Event::LogMessage).first.level.should eq("warning")
      end
    end

    it "lets the event handler call the client" do
      server = new_server.call
      server.on("tools/list") { {"tools" => [{"name" => "fresh", "inputSchema" => {"type" => "object"}}]} }
      connected_client(server) do |client|
        refreshed = [] of String
        client.on_event { |event| refreshed.concat(client.list_tools.map(&.name)) if event.is_a?(MCPC::Event::ToolsChanged) }
        client.connect

        server.push("notifications/tools/list_changed")
        wait_until { refreshed == ["fresh"] }
      end
    end

    it "keeps delivering events after the handler raises" do
      server = new_server.call
      connected_client(server) do |client|
        handled = 0
        client.on_event do
          handled += 1
          raise "handler bug" if handled == 1
        end
        client.connect

        2.times { server.push("notifications/tools/list_changed") }
        wait_until { handled == 2 }
      end
    end

    it "times out a slow request" do
      server = new_server.call
      server.on("tools/call") { FakeServer::SILENT }
      connected_client(server) do |client|
        client.connect
        expect_raises(MCPC::TimeoutError) do
          client.call_tool("slow", options: MCPC::RequestOptions.new(timeout: 30.milliseconds))
        end
      end
    end

    it "reports an unexpected disconnect and fails the requests in flight" do
      server = new_server.call
      server.on("tools/call") { FakeServer::SILENT }
      connected_client(server) do |client, transport|
        log = EventLog.new(client)
        client.connect
        failure = Channel(Exception).new(1)
        spawn do
          client.call_tool("slow")
        rescue error
          failure.send(error)
        end
        wait_until { server.requests_for("tools/call").size == 1 }

        transport.drop("server crashed")

        failure.receive.should be_a(MCPC::ConnectionClosedError)
        log.await(MCPC::Event::Disconnected).reason.should eq("server crashed")
      end
    end

    it "reports no disconnect when the application closes the client" do
      connected_client(new_server.call) do |client, transport|
        log = EventLog.new(client)
        client.connect
        client.close

        transport.closed?.should be_true
        sleep 10.milliseconds
        log.of(MCPC::Event::Disconnected).should be_empty
        expect_raises(MCPC::NotConnectedError) { client.list_tools }
      end
    end
  end
end

describe MCPC::Client do
  describe_common_behaviour("handshake-era") { FakeServer.legacy }
  describe_common_behaviour("stateless") { FakeServer.modern }

  it "refuses to work before it is connected" do
    client = MCPC::Client.new(FakeTransport.new(FakeServer.new))
    expect_raises(MCPC::NotConnectedError) { client.list_tools }
    expect_raises(MCPC::NotConnectedError) { client.server }
  end

  it "opens the transport and describes the server on connect" do
    connected_client(FakeServer.legacy) do |client, transport|
      server = client.connect

      transport.opened?.should be_true
      server.protocol_version.should eq("2025-11-25")
      server.stateless?.should be_false
      server.implementation.try(&.name).should eq("fake-legacy")
      server.instructions.should eq("be kind")
      client.server.should eq(server)
    end
  end

  it "builds stdio and HTTP clients" do
    MCPC::Client.stdio("some-server", ["--flag"]).should be_a(MCPC::Client)
    MCPC::Client.http("https://example.com/mcp", {"Authorization" => "Bearer x"}).should be_a(MCPC::Client)
  end
end
