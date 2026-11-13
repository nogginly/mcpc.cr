module MCPC
  module Era
    # Finds out which era a server belongs to, once per connection.
    class Detector
      DISCOVER       = "server/discover"
      CLIENT_FAULTS  = {Protocol::ErrorCode::HEADER_MISMATCH, Protocol::ErrorCode::MISSING_REQUIRED_CLIENT_CAPABILITY}
      LEGACY_SIGNALS = {400, 404, 405}

      def initialize(@context : Context)
      end

      # Probes with `server/discover` and returns the matching strategy.
      #
      # A discover result means stateless. A timeout, or an error no modern
      # server would send, means handshake. Raises `UnsupportedVersionError`
      # when the server is modern but shares no revision with this client.
      def detect : Strategy
        stateless_or_handshake(discover)
      rescue error : RpcError
        raise error if CLIENT_FAULTS.includes?(error.code)
        handshake_unless_modern_only(error)
      rescue TimeoutError
        Handshake.open(@context)
      rescue error : HttpError
        raise error unless LEGACY_SIGNALS.includes?(error.status)
        Handshake.open(@context)
      end

      private def discover : JSON::Any
        version = Protocol::MODERN_VERSION
        params = RequestMeta.new(version, @context.config, @context.input.capabilities).apply(Params.new)
        call = @context.router.open(DISCOVER, params, RoutingHeaders.new(version).for(DISCOVER, params))
        begin
          call.await(@context.config.probe_timeout)
        rescue error : TimeoutError
          @context.router.forget(call.id)
          @context.transport.abort(call.id)
          raise error
        end
      end

      private def stateless_or_handshake(discovery : JSON::Any) : Strategy
        offered = discovery["supportedVersions"]?.try(&.as_a?.try(&.map(&.as_s))) || [] of String
        if offered.includes?(Protocol::MODERN_VERSION)
          Stateless.new(@context, ServerInfo.from_discovery(discovery, Protocol::MODERN_VERSION))
        else
          handshake_if_offered(offered)
        end
      end

      private def handshake_unless_modern_only(error : RpcError) : Strategy
        return Handshake.open(@context) unless error.code == Protocol::ErrorCode::UNSUPPORTED_PROTOCOL_VERSION
        supported = error.data.try(&.["supported"]?).try(&.as_a?.try(&.map(&.as_s))) || [] of String
        handshake_if_offered(supported)
      end

      private def handshake_if_offered(versions : Array(String)) : Strategy
        return Handshake.open(@context) if versions.any? { |version| Protocol::LEGACY_VERSIONS.includes?(version) }
        raise UnsupportedVersionError.new("server supports only #{versions.join(", ")}")
      end
    end
  end
end
