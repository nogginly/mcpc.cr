module MCPC
  # Names and numbers fixed by the MCP specification.
  module Protocol
    MODERN_VERSION  = "2026-07-28"
    LEGACY_VERSIONS = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]

    module MetaKey
      PROTOCOL_VERSION    = "io.modelcontextprotocol/protocolVersion"
      CLIENT_INFO         = "io.modelcontextprotocol/clientInfo"
      CLIENT_CAPABILITIES = "io.modelcontextprotocol/clientCapabilities"
      LOG_LEVEL           = "io.modelcontextprotocol/logLevel"
      SERVER_INFO         = "io.modelcontextprotocol/serverInfo"
      PROGRESS_TOKEN      = "progressToken"
    end

    module ErrorCode
      PARSE_ERROR                        = -32700
      INVALID_REQUEST                    = -32600
      METHOD_NOT_FOUND                   = -32601
      INVALID_PARAMS                     = -32602
      INTERNAL_ERROR                     = -32603
      RESOURCE_NOT_FOUND                 = -32002
      HEADER_MISMATCH                    = -32020
      MISSING_REQUIRED_CLIENT_CAPABILITY = -32021
      UNSUPPORTED_PROTOCOL_VERSION       = -32022
    end
  end
end
