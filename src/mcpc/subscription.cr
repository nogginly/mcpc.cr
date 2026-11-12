module Mcpc
  # Which change notifications to receive as events.
  struct SubscriptionFilter
    include JSON::Serializable

    @[JSON::Field(key: "toolsListChanged")]
    getter? tools : Bool = false
    @[JSON::Field(key: "promptsListChanged")]
    getter? prompts : Bool = false
    @[JSON::Field(key: "resourcesListChanged")]
    getter? resources : Bool = false
    @[JSON::Field(key: "resourceSubscriptions")]
    getter resource_uris : Array(String) = [] of String

    def initialize(@tools = false, @prompts = false, @resources = false, @resource_uris = [] of String)
    end
  end

  # A running subscription. `filter` is what the server agreed to send,
  # which may be less than was asked for.
  class Subscription
    getter filter : SubscriptionFilter

    def initialize(@filter : SubscriptionFilter, &@on_close : ->)
      @closed = false
    end

    # Stops the notifications. Closing twice is harmless.
    def close : Nil
      return if @closed
      @closed = true
      @on_close.call
    end
  end
end
