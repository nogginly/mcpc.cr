module Mcpc
  # A program's name and version, as it reports them.
  struct Implementation
    include JSON::Serializable

    getter name : String
    getter version : String
    getter title : String?
  end

  # What a server says it can do. `raw` holds the full capabilities object
  # for anything without a named question here.
  struct ServerCapabilities
    getter raw : JSON::Any

    def initialize(@raw : JSON::Any)
    end

    def tools? : Bool
      offers?("tools")
    end

    def resources? : Bool
      offers?("resources")
    end

    def prompts? : Bool
      offers?("prompts")
    end

    def logging? : Bool
      offers?("logging")
    end

    private def offers?(feature : String) : Bool
      !raw[feature]?.nil?
    end
  end

  # What `Client#connect` learned about the server.
  #
  # `instructions` is text written by the server: show it or pass it to a
  # model as untrusted input, never act on it.
  struct ServerInfo
    getter protocol_version : String
    getter capabilities : ServerCapabilities
    getter implementation : Implementation?
    getter instructions : String?

    def initialize(@protocol_version, @capabilities, @implementation = nil, @instructions = nil)
    end

    # True when the server speaks the stateless 2026-07-28 revision.
    def stateless? : Bool
      protocol_version == Protocol::MODERN_VERSION
    end

    # Builds the description from the result of `initialize`.
    def self.from_handshake(result : JSON::Any) : ServerInfo
      new(result["protocolVersion"].as_s, capabilities_in(result),
        implementation_at(result["serverInfo"]?), result["instructions"]?.try(&.as_s?))
    end

    # Builds the description from the result of `server/discover`.
    def self.from_discovery(result : JSON::Any, version : String) : ServerInfo
      described = result.dig?("_meta", Protocol::MetaKey::SERVER_INFO)
      new(version, capabilities_in(result), implementation_at(described), result["instructions"]?.try(&.as_s?))
    end

    private def self.capabilities_in(result : JSON::Any) : ServerCapabilities
      ServerCapabilities.new(result["capabilities"]? || JSON::Any.new(Params.new))
    end

    private def self.implementation_at(described : JSON::Any?) : Implementation?
      described.try { |info| Implementation.from_json(info.to_json) }
    rescue JSON::SerializableError
      nil
    end
  end
end
