module MCPC
  # Data the server offers for reading.
  struct Resource
    include JSON::Serializable

    getter uri : String
    getter name : String
    getter title : String?
    getter description : String?
    @[JSON::Field(key: "mimeType")]
    getter mime_type : String?
    getter size : Int64?
  end

  # A family of resources addressed by an RFC 6570 URI template.
  struct ResourceTemplate
    include JSON::Serializable

    @[JSON::Field(key: "uriTemplate")]
    getter uri_template : String
    getter name : String
    getter title : String?
    getter description : String?
    @[JSON::Field(key: "mimeType")]
    getter mime_type : String?
  end

  # What a resource holds: `text`, or base64 in `blob` for binary data.
  struct ResourceContents
    include JSON::Serializable

    getter uri : String
    @[JSON::Field(key: "mimeType")]
    getter mime_type : String?
    getter text : String?
    getter blob : String?
  end
end
