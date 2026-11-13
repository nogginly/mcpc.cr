require "../../spec_helper"
require "../../../apps/probe/probe"

ALL_CAPABILITIES = {"tools" => {"listChanged" => true}, "resources" => {} of String => String, "prompts" => {} of String => String}

# A handshake-era server that advertises and serves every kind of list.
def well_stocked_server : FakeServer
  FakeServer.legacy(capabilities: ALL_CAPABILITIES).tap do |server|
    server.on("tools/list") { {"tools" => [{"name" => "echo", "description" => "Echoes input", "inputSchema" => {"type" => "object"}}]} }
    server.on("resources/list") { {"resources" => [{"uri" => "file:///todo.md", "name" => "todo"}]} }
    server.on("resources/templates/list") { {"resourceTemplates" => [{"uriTemplate" => "weather://{city}", "name" => "daily", "description" => "Daily weather"}]} }
    server.on("prompts/list") { {"prompts" => [{"name" => "review", "description" => "Review code"}]} }
  end
end

def survey(server : FakeServer) : {McpcProbe::Report, FakeTransport}
  transport = FakeTransport.new(server)
  client = Mcpc::Client.new(transport, fast_config)
  {McpcProbe::Survey.new(client, "fake-target").run, transport}
end

def no_environment : Hash(String, String)
  {} of String => String
end
