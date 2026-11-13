module McpcProbe
  # One thing a server listed: a tool, resource, template or prompt.
  record Item, name : String, description : String? = nil

  # One list a server advertises. `error` says why it could not be read.
  record Section, title : String, items : Array(Item) = [] of Item, error : String? = nil

  # What probing one server found.
  class Report
    getter target : String

    # What the server said about itself; nil when the connection failed.
    property server : Mcpc::ServerInfo?

    # Why the connection failed; nil when it succeeded.
    property failure : String?

    getter sections = [] of Section

    def initialize(@target : String)
    end

    def connected? : Bool
      !server.nil?
    end

    # True when the server connected and everything it advertises could be read.
    def ok? : Bool
      connected? && sections.none?(&.error)
    end
  end
end
