# A scripted MCP server. Register a block per method; the block's value
# becomes the result. Unregistered methods get "method not found".
class FakeServer
  # Raise from a handler to answer with a JSON-RPC error.
  class Fault < Exception
    getter code : Int32
    getter data : JSON::Any?

    def initialize(@code, message : String, data = nil)
      super(message)
      @data = data.try { |value| Mcpc::Json.any(value) }
    end
  end

  # Return from a handler to send no response at all.
  SILENT = Silence.new

  struct Silence
  end

  # What a handler uses to send messages that belong to the request in hand.
  class Exchange
    def initialize(@emit : Mcpc::JsonRpc::Message ->)
    end

    def notify(method : String, params = nil) : Nil
      @emit.call(Mcpc::JsonRpc::Notification.new(method, params.try { |value| Mcpc::Json.any(value) }))
    end

    def ask(id : Mcpc::JsonRpc::Id, method : String, params) : Nil
      @emit.call(Mcpc::JsonRpc::Request.new(id, method, Mcpc::Json.any(params)))
    end
  end

  alias Request = Mcpc::JsonRpc::Request
  alias Handler = Request, Exchange -> JSON::Any | Silence

  getter requests = [] of Request
  getter notifications = [] of Mcpc::JsonRpc::Notification
  getter responses = [] of Mcpc::JsonRpc::Response

  def initialize
    @handlers = {} of String => Handler
    @outbound = ->(_message : Mcpc::JsonRpc::Message) { }
  end

  # A server of the handshake era.
  def self.legacy(version = "2025-11-25", capabilities = {"tools" => {"listChanged" => true}}) : FakeServer
    new.tap do |server|
      server.on("initialize") do
        {"protocolVersion" => version, "capabilities" => capabilities,
         "serverInfo" => {"name" => "fake-legacy", "version" => "1.0.0"}, "instructions" => "be kind"}
      end
    end
  end

  # A server of the stateless era.
  def self.modern(versions = ["2026-07-28"]) : FakeServer
    new.tap do |server|
      server.on("server/discover") do
        {"resultType" => "complete", "supportedVersions" => versions, "capabilities" => {"tools" => {} of String => String},
         "ttlMs" => 1000, "cacheScope" => "public",
         "_meta" => {"io.modelcontextprotocol/serverInfo" => {"name" => "fake-modern", "version" => "2.0.0"}}}
      end
    end
  end

  def on(method : String, &block : Request, Exchange -> T) : Nil forall T
    @handlers[method] = ->(request : Request, exchange : Exchange) : JSON::Any | Silence {
      value = block.call(request, exchange)
      value.is_a?(Silence) ? value : Mcpc::Json.any(value)
    }
  end

  # Answers *method* with a JSON-RPC error.
  def fail_with(method : String, code : Int32, message : String, data = nil) : Nil
    @handlers[method] = ->(_request : Request, _exchange : Exchange) : JSON::Any | Silence {
      raise Fault.new(code, message, data)
    }
  end

  # Where messages sent outside any request go.
  def connect(&@outbound : Mcpc::JsonRpc::Message ->) : Nil
  end

  # Sends a notification that belongs to no request.
  def push(method : String, params = nil) : Nil
    Exchange.new(@outbound).notify(method, params)
  end

  # Sends a request to the client.
  def ask(id : Mcpc::JsonRpc::Id, method : String, params) : Nil
    Exchange.new(@outbound).ask(id, method, params)
  end

  # Handles one inbound message, emitting what it produces through *emit*.
  def receive(message : Mcpc::JsonRpc::Message, emit : Mcpc::JsonRpc::Message -> = @outbound) : Nil
    case message
    in Mcpc::JsonRpc::Request      then answer(message, emit)
    in Mcpc::JsonRpc::Notification then notifications << message
    in Mcpc::JsonRpc::Response     then responses << message
    end
  end

  def requests_for(method : String) : Array(Request)
    requests.select { |request| request.method == method }
  end

  def last_request(method : String) : Request
    requests_for(method).last
  end

  private def answer(request : Request, emit : Mcpc::JsonRpc::Message ->)
    requests << request
    handler = @handlers[request.method]? || raise Fault.new(-32601, "Method not found")
    result = handler.call(request, Exchange.new(emit))
    emit.call(Mcpc::JsonRpc::Response.success(request.id, result)) if result.is_a?(JSON::Any)
  rescue error : Fault
    refusal = Mcpc::JsonRpc::ErrorObject.new(error.code, error.message || "", error.data)
    emit.call(Mcpc::JsonRpc::Response.new(request.id, error: refusal))
  end
end
