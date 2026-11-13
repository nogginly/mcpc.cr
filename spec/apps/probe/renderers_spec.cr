require "./spec_helper"

private def text_of(report : MCPCProbe::Report) : String
  String.build { |io| MCPCProbe::TextRenderer.new(io).render(report) }
end

private def json_of(report : MCPCProbe::Report) : JSON::Any
  JSON.parse(String.build { |io| MCPCProbe::JSONRenderer.new(io).render(report) })
end

private def failed_report : MCPCProbe::Report
  MCPCProbe::Report.new("https://example.com/mcp").tap(&.failure=("The server did not answer in time."))
end

describe MCPCProbe::TextRenderer do
  it "shows the server, its era, its capabilities and each list" do
    text = text_of(survey(well_stocked_server)[0])

    text.should contain("Target    fake-target")
    text.should contain("Result    connected\n")
    text.should contain("Server    fake-legacy 1.0.0")
    text.should contain("Protocol  2025-11-25 (handshake era)")
    text.should contain(%(  tools                        {"listChanged":true}))
    text.should contain("Tools (1)\n  echo                         Echoes input")
    text.should contain("Resource templates (1)\n  weather://{city}             Daily weather")
    text.should contain("Instructions (written by the server)\n  be kind")
  end

  it "says so when a server advertises nothing" do
    text_of(survey(FakeServer.legacy(capabilities: {} of String => String))[0]).should contain("none advertised")
  end

  it "shows a failed connection and nothing else" do
    text_of(failed_report).should eq("Target    https://example.com/mcp\nResult    FAILED. The server did not answer in time.\n")
  end

  it "flags a list that could not be read" do
    server = well_stocked_server
    server.fail_with("prompts/list", -32603, "boom")
    text = text_of(survey(server)[0])

    text.should contain("Result    connected, with problems")
    text.should contain("Prompts\n  FAILED. The server refused the request: boom (code -32603).")
  end

  it "removes control characters from what the server wrote" do
    server = FakeServer.legacy
    server.on("tools/list") do
      {"tools" => [{"name" => "evil\e[2J", "description" => "clears\e[31m the screen\nsecond line", "inputSchema" => {"type" => "object"}}]}
    end
    text = text_of(survey(server)[0])

    text.should_not contain('\e')
    text.should contain("clears [31m the screen")
    text.should_not contain("second line")
  end

  it "shortens a long description and keeps a long name whole" do
    server = FakeServer.legacy
    name = "tool-" + "n" * 60
    server.on("tools/list") { {"tools" => [{"name" => name, "description" => "d" * 200, "inputSchema" => {"type" => "object"}}]} }
    text = text_of(survey(server)[0])

    text.should contain(name)
    text.should contain("d" * 79 + "…")
    text.should_not contain("d" * 81)
  end
end

describe MCPCProbe::JSONRenderer do
  it "writes the whole report as JSON" do
    json = json_of(survey(well_stocked_server)[0])

    json["target"].should eq("fake-target")
    json["ok"].should be_true
    json["failure"].raw.should be_nil
    json["protocolVersion"].should eq("2025-11-25")
    json["stateless"].should be_false
    json["serverName"].should eq("fake-legacy")
    json["capabilities"]["tools"]["listChanged"].should be_true
    json["instructions"].should eq("be kind")
    json["sections"].as_a.map(&.["title"].as_s).should eq(["Tools", "Resources", "Resource templates", "Prompts"])
    json["sections"][0]["items"][0].should eq(JSON.parse(%({"name":"echo","description":"Echoes input"})))
  end

  it "writes a failed connection" do
    json = json_of(failed_report)
    json["ok"].should be_false
    json["failure"].should eq("The server did not answer in time.")
    json["sections"].as_a.should be_empty
    json.as_h.has_key?("protocolVersion").should be_false
  end
end
