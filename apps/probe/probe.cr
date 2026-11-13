require "../../src/mcpc"
require "option_parser"
require "./target"
require "./options"
require "./report"
require "./diagnosis"
require "./survey"
require "./clean_text"
require "./text_renderer"
require "./json_renderer"
require "./cli"

# Connects to one MCP server and reports what it advertises, to show
# whether the server works with this shard's client.
module McpcProbe
  NAME = "mcpc-probe"
end
