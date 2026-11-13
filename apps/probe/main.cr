# The `mcpc-probe` command. Build it with `shards build`.
require "./probe"

exit MCPCProbe::CLI.new(ARGV, ENV.to_h).run
