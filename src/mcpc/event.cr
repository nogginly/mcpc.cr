module Mcpc
  # Something the server or the connection reported without being asked.
  # `Client#on_event` receives every one; match on the concrete type.
  #
  # ```
  # client.on_event do |event|
  #   case event
  #   when Mcpc::Event::Progress     then puts "#{event.progress} of #{event.total}"
  #   when Mcpc::Event::ToolsChanged then refresh_tools
  #   end
  # end
  # ```
  abstract struct Event
    # A request made with `RequestOptions#progress_token` moved forward.
    struct Progress < Event
      include JSON::Serializable

      @[JSON::Field(key: "progressToken")]
      getter token : String | Int64
      getter progress : Float64
      getter total : Float64?
      getter message : String?
    end

    # The server logged something. `data` is any JSON value.
    struct LogMessage < Event
      include JSON::Serializable

      getter level : String
      getter logger : String?
      getter data : JSON::Any
    end

    # The list of tools changed; `Client#list_tools` returns the new one.
    struct ToolsChanged < Event
    end

    # The list of prompts changed.
    struct PromptsChanged < Event
    end

    # The list of resources changed.
    struct ResourcesChanged < Event
    end

    # A subscribed resource changed; read it again for the new contents.
    struct ResourceUpdated < Event
      include JSON::Serializable

      getter uri : String
    end

    # The server ended a subscription. `reason` is nil for an orderly end.
    struct SubscriptionClosed < Event
      getter reason : String?

      def initialize(@reason : String? = nil)
      end
    end

    # The connection ended without `Client#close` being called.
    struct Disconnected < Event
      getter reason : String?

      def initialize(@reason : String? = nil)
      end
    end
  end
end
