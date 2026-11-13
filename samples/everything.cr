# Connects to the MCP reference server and exercises the client.
#
#   crystal run samples/everything.cr
#
# Needs Node, for `npx`.
require "../src/mcpc"

client = MCPC::Client.stdio("npx", ["-y", "@modelcontextprotocol/server-everything"])

client.on_event do |event|
  case event
  when MCPC::Event::Progress     then puts "  progress #{event.progress}/#{event.total}"
  when MCPC::Event::LogMessage   then puts "  server log [#{event.level}] #{event.data}"
  when MCPC::Event::Disconnected then puts "  disconnected: #{event.reason}"
  else                                puts "  event: #{event.class.name}"
  end
end

client.on_elicitation do |request|
  puts "  server asks: #{request.message}"
  request.decline
end

server = client.connect
puts "Connected to #{server.implementation.try(&.name)} speaking #{server.protocol_version}"

puts "Tools:"
client.list_tools.each { |tool| puts "  #{tool.name}: #{tool.description}" }

puts "Calling echo:"
puts "  #{client.call_tool("echo", {"message" => "hello from Crystal"}).text}"

puts "Calling a slow tool with progress:"
options = MCPC::RequestOptions.new(progress_token: "demo", timeout: 30.seconds)
client.call_tool("trigger-long-running-operation", {"duration" => 2, "steps" => 4}, options)

puts "Resources: #{client.list_resources.size}, prompts: #{client.list_prompts.size}"
client.close
