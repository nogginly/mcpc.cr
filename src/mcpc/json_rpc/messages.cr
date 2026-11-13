module MCPC
  # The JSON-RPC 2.0 envelope every MCP message travels in.
  module JSONRPC
    VERSION = "2.0"

    # Request ids are strings or integers, echoed back with the same type.
    alias Id = String | Int64

    struct ErrorObject
      include JSON::Serializable

      getter code : Int32
      getter message : String
      getter data : JSON::Any?

      def initialize(@code, @message, @data = nil)
      end
    end

    # Expects a `Response` carrying the same id.
    struct Request
      include JSON::Serializable

      getter jsonrpc : String = VERSION
      getter id : Id
      getter method : String
      getter params : JSON::Any?

      def initialize(@id, @method, @params = nil)
      end
    end

    # Expects no reply.
    struct Notification
      include JSON::Serializable

      getter jsonrpc : String = VERSION
      getter method : String
      getter params : JSON::Any?

      def initialize(@method, @params = nil)
      end
    end

    # Carries either `result` or `error`, never both.
    struct Response
      include JSON::Serializable

      getter jsonrpc : String = VERSION
      getter id : Id?
      getter result : JSON::Any?
      getter error : ErrorObject?

      def initialize(@id, @result = nil, @error = nil)
      end

      def self.success(id : Id, result : JSON::Any) : Response
        new(id, result: result)
      end

      def self.failure(id : Id?, code : Int32, message : String) : Response
        new(id, error: ErrorObject.new(code, message))
      end
    end

    alias Message = Request | Notification | Response

    # Text that is not one JSON-RPC message.
    class InvalidMessage < MCPC::ProtocolError
    end

    # Reads one message, choosing its type by shape: a `method` with an `id`
    # is a request, a `method` alone is a notification, anything with
    # `result` or `error` is a response.
    def self.parse(text : String) : Message
      shape = JSON.parse(text).as_h? || raise InvalidMessage.new("not a JSON object")
      if shape.has_key?("method")
        shape.has_key?("id") ? Request.from_json(text) : Notification.from_json(text)
      elsif shape.has_key?("result") || shape.has_key?("error")
        Response.from_json(text)
      else
        raise InvalidMessage.new("neither request, notification nor response")
      end
    rescue error : JSON::ParseException
      raise InvalidMessage.new(error.message)
    end
  end
end
