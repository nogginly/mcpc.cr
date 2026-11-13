module MCPC
  # Settings a client is created with. Change them before `Client#connect`.
  class Config
    # How this client names itself to servers.
    property client_name : String = "mcpc"
    property client_version : String = VERSION

    # How long a request may wait for its response, unless the request says otherwise.
    property request_timeout : Time::Span = 60.seconds

    # How long to wait for a `server/discover` answer before assuming a handshake-era server.
    property probe_timeout : Time::Span = 5.seconds

    # How many times one request may be retried with further input before giving up.
    property max_input_rounds : Int32 = 8

    # The least severe server log level to receive as `Event::LogMessage`
    # ("debug", "info", "warning", "error", ...). `nil` asks for none.
    property log_level : String? = nil

    def client_info : JSON::Any
      JSONValue.any({"name" => client_name, "version" => client_version})
    end
  end
end
