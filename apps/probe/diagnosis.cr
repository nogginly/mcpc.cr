module MCPCProbe
  # Says what went wrong in terms a person can act on.
  module Diagnosis
    def self.of(error : Exception) : String
      case error
      when MCPC::HttpError               then http(error)
      when MCPC::RpcError                then "The server refused the request: #{error.message} (code #{error.code})."
      when MCPC::TimeoutError            then "The server did not answer in time."
      when MCPC::UnsupportedVersionError then "No protocol revision in common: #{error.message}."
      when MCPC::ProtocolError           then "The server sent something this client cannot read: #{error.message}."
      when MCPC::TransportError          then "The server could not be reached: #{error.message}."
      else                                    "#{error.class.name}: #{error.message}"
      end
    end

    private def self.http(error : MCPC::HttpError) : String
      case error.status
      when 401, 403
        "The server refused the credentials (HTTP #{error.status}). This client has no OAuth; " \
        "pass a token with --bearer-env, --header-env or --header."
      when 404
        "Nothing answers at that address (HTTP 404). Check the path; it often ends in /mcp."
      else
        "The server answered HTTP #{error.status}."
      end
    end
  end
end
