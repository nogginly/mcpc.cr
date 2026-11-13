require "../spec_helper"

private def params(json : String) : MCPC::Params
  JSON.parse(json).as_h
end

private def tool(name : String, schema : String) : MCPC::Tool
  MCPC::Tool.from_json(%({"name":#{name.to_json},"inputSchema":#{schema}}))
end

describe MCPC::Era::RoutingHeaders do
  it "mirrors the version and method of every request" do
    headers = MCPC::Era::RoutingHeaders.new("2026-07-28").for("tools/list", MCPC::Params.new)
    headers.should eq({"MCP-Protocol-Version" => "2026-07-28", "Mcp-Method" => "tools/list"})
  end

  it "names the tool of tools/call" do
    headers = MCPC::Era::RoutingHeaders.new("2026-07-28").for("tools/call", params(%({"name":"get_weather"})))
    headers["Mcp-Name"].should eq("get_weather")
  end

  it "names the prompt of prompts/get" do
    headers = MCPC::Era::RoutingHeaders.new("2026-07-28").for("prompts/get", params(%({"name":"review"})))
    headers["Mcp-Name"].should eq("review")
  end

  it "names the URI of resources/read" do
    headers = MCPC::Era::RoutingHeaders.new("2026-07-28").for("resources/read", params(%({"uri":"file:///a.json"})))
    headers["Mcp-Name"].should eq("file:///a.json")
  end

  it "encodes a name that is unsafe in a header" do
    headers = MCPC::Era::RoutingHeaders.new("2026-07-28").for("tools/call", params(%({"name":"météo"})))
    headers["Mcp-Name"].should eq("=?base64?#{Base64.strict_encode("météo")}?=")
  end

  it "mirrors the annotated arguments of a tool it has learned" do
    routing = MCPC::Era::RoutingHeaders.new("2026-07-28")
    schema = %({"type":"object","properties":{"region":{"type":"string","x-mcp-header":"Region"}}})
    routing.learn(tool("execute_sql", schema)).should be_true

    headers = routing.for("tools/call", params(%({"name":"execute_sql","arguments":{"region":"us-west1"}})))
    headers["Mcp-Param-Region"].should eq("us-west1")
  end

  it "adds no argument headers for a tool it has not learned" do
    headers = MCPC::Era::RoutingHeaders.new("2026-07-28")
      .for("tools/call", params(%({"name":"other","arguments":{"region":"us-west1"}})))
    headers.keys.should eq(["MCP-Protocol-Version", "Mcp-Method", "Mcp-Name"])
  end

  it "turns away a tool whose annotations are invalid" do
    routing = MCPC::Era::RoutingHeaders.new("2026-07-28")
    schema = %({"type":"object","properties":{"ratio":{"type":"number","x-mcp-header":"Ratio"}}})
    routing.learn(tool("broken", schema)).should be_false
  end
end
