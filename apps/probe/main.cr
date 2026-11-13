# The `mcpc-probe` command. Build it with `shards build`.
require "./probe"

exit McpcProbe::Cli.new(ARGV, ENV.to_h).run
