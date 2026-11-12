module Mcpc
  # A connection to one MCP server.
  #
  # ```
  # client = Mcpc::Client.stdio("npx", ["-y", "@modelcontextprotocol/server-everything"])
  # client.on_event { |event| puts event }
  # client.connect
  # client.list_tools.each { |tool| puts tool.name }
  # puts client.call_tool("echo", {"message" => "hello"}).text
  # client.close
  # ```
  #
  # Methods that talk to the server block the calling fiber and raise
  # `RpcError` when the server refuses, `TimeoutError` when it is too slow,
  # and `TransportError` when it cannot be reached.
  class Client
    DEFAULT_OPTIONS = RequestOptions.new

    # A client for a server run as a subprocess.
    def self.stdio(command : String, args = [] of String, env : Process::Env = nil, config = Config.new) : Client
      new(Transport::Stdio.new(command, args, env), config)
    end

    # A client for a server at a Streamable HTTP endpoint. *headers* go
    # with every request; use them for credentials.
    def self.http(url : String, headers = Transport::Headers.new, config = Config.new) : Client
      new(Transport::StreamableHttp.new(url, headers), config)
    end

    def initialize(@transport : Transport, @config = Config.new)
      @events = EventDispatcher.new
      @input = ClientInput.new
      @era = nil.as(Era::Strategy?)
      @closing = false
    end

    # Registers the one handler that receives every `Event`. Events are
    # delivered in order on their own fiber.
    def on_event(&handler : Event ->) : Nil
      @events.on_event(&handler)
    end

    # Registers the handler that answers a server's questions for the user.
    # Register it before `connect`: servers are only told the client can
    # answer if a handler exists by then.
    def on_elicitation(&handler : ElicitationRequest -> ElicitationResponse) : Nil
      @input.elicitation_handler = handler
    end

    # Opens the connection, works out which protocol revision the server
    # speaks, and returns what the server said about itself. A failed
    # attempt leaves the connection closed.
    def connect : ServerInfo
      @transport.open
      router = JsonRpc::Router.new(@transport)
      router.on_close { |error| report_disconnect(error) }
      @era = Era::Detector.new(Era::Context.new(router, @transport, @config, @events, @input)).detect
      server
    rescue error
      @closing = true
      @transport.close
      raise error
    end

    # Ends the connection. The client cannot be used afterwards.
    def close : Nil
      @closing = true
      @era = nil
      @transport.close
      @events.close
    end

    def server : ServerInfo
      era.server
    end

    # Every tool the server offers.
    def list_tools(options = DEFAULT_OPTIONS) : Array(Tool)
      era.admit(list("tools/list", "tools", Tool, options))
    end

    # Runs a tool. A tool that fails returns a result whose `error?` is
    # true; only protocol problems raise.
    def call_tool(name : String, arguments = nil, options = DEFAULT_OPTIONS) : CallToolResult
      params = Params{"name" => JSON::Any.new(name)}
      params["arguments"] = Json.any(arguments) unless arguments.nil?
      decoding("tools/call") { CallToolResult.from_json(request("tools/call", params, options).to_json) }
    end

    def list_resources(options = DEFAULT_OPTIONS) : Array(Resource)
      list("resources/list", "resources", Resource, options)
    end

    def list_resource_templates(options = DEFAULT_OPTIONS) : Array(ResourceTemplate)
      list("resources/templates/list", "resourceTemplates", ResourceTemplate, options)
    end

    def read_resource(uri : String, options = DEFAULT_OPTIONS) : Array(ResourceContents)
      result = request("resources/read", Params{"uri" => JSON::Any.new(uri)}, options)
      decoding("resources/read") { Array(ResourceContents).from_json(result["contents"].to_json) }
    end

    def list_prompts(options = DEFAULT_OPTIONS) : Array(Prompt)
      list("prompts/list", "prompts", Prompt, options)
    end

    def get_prompt(name : String, arguments : Hash(String, String)? = nil, options = DEFAULT_OPTIONS) : PromptResult
      params = Params{"name" => JSON::Any.new(name)}
      params["arguments"] = Json.any(arguments) if arguments
      decoding("prompts/get") { PromptResult.from_json(request("prompts/get", params, options).to_json) }
    end

    # Asks for change notifications, which then arrive as events until the
    # returned `Subscription` is closed.
    def subscribe(filter : SubscriptionFilter) : Subscription
      era.subscribe(filter)
    end

    # Sends any request and returns its raw result, for methods this class
    # has no named method for. *params* is anything that serializes to a
    # JSON object.
    def request(method : String, params = Params.new, options = DEFAULT_OPTIONS) : JSON::Any
      era.request(method, Json.any(params).as_h, options)
    end

    private def list(method : String, key : String, type : T.class, options : RequestOptions) : Array(T) forall T
      decoding(method) do
        Pagination.collect(key, type) do |cursor|
          params = Params.new
          params["cursor"] = JSON::Any.new(cursor) if cursor
          request(method, params, options)
        end
      end
    end

    # Runs the block, reporting a result of the wrong shape as `ProtocolError`.
    private def decoding(method : String, &)
      yield
    rescue error : JSON::ParseException | KeyError | TypeCastError
      raise ProtocolError.new("unexpected #{method} result: #{error.message}")
    end

    private def era : Era::Strategy
      @era || raise NotConnectedError.new
    end

    private def report_disconnect(error : Exception?)
      @events.emit(Event::Disconnected.new(error.try(&.message))) unless @closing
    end
  end
end
