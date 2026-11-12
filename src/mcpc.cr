require "json"
require "log"
require "./mcpc/version"
require "./mcpc/errors"
require "./mcpc/protocol"
require "./mcpc/json"
require "./mcpc/config"
require "./mcpc/cancellation"
require "./mcpc/request_options"
require "./mcpc/json_rpc/*"
require "./mcpc/transport"
require "./mcpc/transport/*"
require "./mcpc/types/*"
require "./mcpc/event"
require "./mcpc/event_dispatcher"
require "./mcpc/notification_events"
require "./mcpc/elicitation"
require "./mcpc/client_input"
require "./mcpc/subscription"
require "./mcpc/era/context"
require "./mcpc/era/strategy"
require "./mcpc/era/*"
require "./mcpc/pagination"
require "./mcpc/client"

# A Model Context Protocol client. Start at `Mcpc::Client`.
module Mcpc
  Log = ::Log.for("mcpc")
end
