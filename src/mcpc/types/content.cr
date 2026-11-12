module Mcpc
  # One block of a tool result or prompt message. Match on the concrete
  # type: `TextContent`, `ImageContent`, `AudioContent`, `ResourceLink`,
  # `EmbeddedResource`, or `UnknownContent` for types this shard predates.
  abstract struct Content
    def self.new(pull : JSON::PullParser) : Content
      from_any(JSON::Any.new(pull))
    end

    def self.from_any(block : JSON::Any) : Content
      json = block.to_json
      case block["type"]?.try(&.as_s?)
      when "text"          then TextContent.from_json(json)
      when "image"         then ImageContent.from_json(json)
      when "audio"         then AudioContent.from_json(json)
      when "resource_link" then ResourceLink.from_json(json)
      when "resource"      then EmbeddedResource.from_json(json)
      else                      UnknownContent.new(block)
      end
    end
  end

  struct TextContent < Content
    include JSON::Serializable

    getter text : String
  end

  # `data` is base64.
  struct ImageContent < Content
    include JSON::Serializable

    getter data : String
    @[JSON::Field(key: "mimeType")]
    getter mime_type : String
  end

  # `data` is base64.
  struct AudioContent < Content
    include JSON::Serializable

    getter data : String
    @[JSON::Field(key: "mimeType")]
    getter mime_type : String
  end

  # Points at a resource to fetch with `Client#read_resource`.
  struct ResourceLink < Content
    include JSON::Serializable

    getter uri : String
    getter name : String
    getter title : String?
    getter description : String?
    @[JSON::Field(key: "mimeType")]
    getter mime_type : String?
  end

  # Carries a resource's contents inline.
  struct EmbeddedResource < Content
    include JSON::Serializable

    getter resource : ResourceContents
  end

  struct UnknownContent < Content
    getter raw : JSON::Any

    def initialize(@raw : JSON::Any)
    end
  end
end
