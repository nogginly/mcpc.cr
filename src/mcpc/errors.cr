module MCPC
  # Base class of every error this shard raises.
  class Error < Exception
  end

  # The server answered a request with a JSON-RPC error.
  class RpcError < Error
    getter code : Int32
    getter data : JSON::Any?

    def initialize(@code : Int32, message : String, @data : JSON::Any? = nil)
      super(message)
    end
  end

  # The server sent something the protocol does not allow.
  class ProtocolError < Error
  end

  # Client and server share no protocol revision.
  class UnsupportedVersionError < ProtocolError
  end

  # The server asked for input this client cannot supply.
  class InputRequiredError < Error
  end

  # No response arrived within the allowed time.
  class TimeoutError < Error
    def initialize(message = "request timed out")
      super
    end
  end

  # The application cancelled the request.
  class CancelledError < Error
    def initialize(message = nil)
      super(message || "request cancelled")
    end
  end

  # A client method was called before `Client#connect` or after `Client#close`.
  class NotConnectedError < Error
    def initialize
      super("client is not connected")
    end
  end

  # The message could not be carried to or from the server.
  class TransportError < Error
  end

  # The connection ended while a response was still expected.
  class ConnectionClosedError < TransportError
    def initialize(message = "connection closed")
      super
    end
  end

  # The server refused a request at the HTTP level.
  class HttpError < TransportError
    getter status : Int32
    getter body : String

    def initialize(@status : Int32, @body : String = "")
      super("HTTP #{@status}")
    end
  end

  # The server no longer recognises the HTTP session; connect again.
  class SessionExpiredError < HttpError
  end
end
