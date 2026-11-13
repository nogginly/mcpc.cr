module MCPC
  module Era
    # The HTTP headers that mirror a 2026-07-28 request, so that proxies can
    # route it without reading the body.
    class RoutingHeaders
      NAME_SOURCE = {"tools/call" => "name", "prompts/get" => "name", "resources/read" => "uri"}

      def initialize(@version : String)
        @annotations = {} of String => HeaderAnnotations
      end

      # Remembers which arguments of *tool* the server wants mirrored.
      # Returns false, and forgets the tool, when its annotations are invalid.
      def learn(tool : Tool) : Bool
        @annotations[tool.name] = HeaderAnnotations.new(tool.input_schema)
        true
      rescue error : HeaderAnnotations::Invalid
        @annotations.delete(tool.name)
        Log.warn { "tool #{tool.name} left out: #{error.message}" }
        false
      end

      def for(method : String, params : Params) : Transport::Headers
        headers = Transport::Headers{"MCP-Protocol-Version" => @version, "Mcp-Method" => method}
        name = NAME_SOURCE[method]?.try { |key| params[key]?.try(&.as_s?) }
        headers["Mcp-Name"] = HeaderValue.encode(name) if name
        headers.merge!(argument_headers(name, params)) if method == "tools/call"
        headers
      end

      private def argument_headers(tool_name : String?, params : Params) : Transport::Headers
        annotations = tool_name.try { |name| @annotations[name]? } || return Transport::Headers.new
        annotations.mirror(params["arguments"]?)
      end
    end
  end
end
