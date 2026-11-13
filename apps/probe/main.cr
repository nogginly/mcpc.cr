# The `mcpc-probe` command. Build it with `shards build`.
require "./probe"

exit MCPCProbe::Cli.new(ARGV, ENV.to_h).run
