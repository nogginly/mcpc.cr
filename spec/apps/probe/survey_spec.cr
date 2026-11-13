require "./spec_helper"

describe MCPCProbe::Survey do
  it "collects every list a server advertises" do
    report, _ = survey(well_stocked_server)

    report.ok?.should be_true
    report.target.should eq("fake-target")
    report.server.try(&.protocol_version).should eq("2025-11-25")
    report.sections.map(&.title).should eq(["Tools", "Resources", "Resource templates", "Prompts"])
    report.sections.map(&.items.map(&.name)).should eq([["echo"], ["file:///todo.md"], ["weather://{city}"], ["review"]])
    report.sections.first.items.first.description.should eq("Echoes input")
  end

  it "describes a resource by its name when it has no description" do
    report, _ = survey(well_stocked_server)
    report.sections[1].items.first.description.should eq("todo")
  end

  it "asks only for what the server advertises" do
    server = FakeServer.legacy(capabilities: {"prompts" => {} of String => String})
    server.on("prompts/list") { {"prompts" => [] of String} }
    report, _ = survey(server)

    report.sections.map(&.title).should eq(["Prompts"])
    server.requests.map(&.method).should eq(["server/discover", "initialize", "prompts/list"])
  end

  it "works with a stateless server" do
    server = FakeServer.modern
    server.on("tools/list") { {"tools" => [{"name" => "add", "inputSchema" => {"type" => "object"}}]} }
    report, _ = survey(server)

    report.ok?.should be_true
    report.server.try(&.stateless?).should be_true
    report.sections.first.items.map(&.name).should eq(["add"])
  end

  it "records a list that cannot be read and carries on with the rest" do
    server = well_stocked_server
    server.fail_with("resources/list", -32603, "database is down")
    report, _ = survey(server)

    report.connected?.should be_true
    report.ok?.should be_false
    report.sections[1].error.should eq("The server refused the request: database is down (code -32603).")
    report.sections.last.items.map(&.name).should eq(["review"])
  end

  it "records why a connection failed" do
    server = FakeServer.new
    server.fail_with("server/discover", -32021, "Missing required client capability")
    report, _ = survey(server)

    report.connected?.should be_false
    report.ok?.should be_false
    report.failure.should eq("The server refused the request: Missing required client capability (code -32021).")
    report.sections.should be_empty
  end

  it "closes the connection, whatever happened" do
    _, transport = survey(well_stocked_server)
    transport.closed?.should be_true

    _, failed_transport = survey(FakeServer.legacy(version: "1999-01-01"))
    failed_transport.closed?.should be_true
  end
end
