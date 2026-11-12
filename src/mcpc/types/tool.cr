module Mcpc
  # A server's hints about a tool's behaviour. Hints from an untrusted
  # server are untrusted.
  struct ToolAnnotations
    include JSON::Serializable

    getter title : String?
    @[JSON::Field(key: "readOnlyHint")]
    getter read_only_hint : Bool?
    @[JSON::Field(key: "destructiveHint")]
    getter destructive_hint : Bool?
    @[JSON::Field(key: "idempotentHint")]
    getter idempotent_hint : Bool?
    @[JSON::Field(key: "openWorldHint")]
    getter open_world_hint : Bool?
  end

  # Something the server can do on request. `name` identifies it, `title`
  # is for people, and both schemas are JSON Schema.
  struct Tool
    include JSON::Serializable

    getter name : String
    getter title : String?
    getter description : String?
    @[JSON::Field(key: "inputSchema")]
    getter input_schema : JSON::Any
    @[JSON::Field(key: "outputSchema")]
    getter output_schema : JSON::Any?
    getter annotations : ToolAnnotations?
  end

  # What a tool returned. A tool that failed still returns a result, with
  # `error?` true and the reason in `content`.
  struct CallToolResult
    include JSON::Serializable

    getter content : Array(Content) = [] of Content
    @[JSON::Field(key: "structuredContent")]
    getter structured_content : JSON::Any?
    @[JSON::Field(key: "isError")]
    getter? error : Bool = false

    # The text blocks of `content`, joined by newlines.
    def text : String
      content.compact_map(&.as?(TextContent)).join('\n', &.text)
    end
  end
end
