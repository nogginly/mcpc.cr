module MCPC
  module Era
    # The 2024-11-05 to 2025-11-25 revisions: the connection opens with
    # `initialize`, and the server may send requests of its own.
    class Handshake < Strategy
      PREFERRED_VERSION = Protocol::LEGACY_VERSIONS.first
      VERSION_HEADER    = "MCP-Protocol-Version"

      # Performs the handshake and returns the strategy for the connection.
      # Raises `UnsupportedVersionError` when the server insists on a
      # revision this client does not speak.
      def self.open(context : Context) : Handshake
        result = context.router.open("initialize", opening_params(context)).await(context.config.request_timeout)
        server = ServerInfo.from_handshake(result)
        unless Protocol::LEGACY_VERSIONS.includes?(server.protocol_version)
          raise UnsupportedVersionError.new("server speaks #{server.protocol_version}")
        end
        new(context, server).tap(&.announce_ready)
      end

      def self.opening_params(context : Context) : Params
        Params{
          "protocolVersion" => JSON::Any.new(PREFERRED_VERSION),
          "capabilities"    => context.input.capabilities,
          "clientInfo"      => context.config.client_info,
        }
      end

      def initialize(context : Context, server : ServerInfo)
        super
        @headers = Transport::Headers{VERSION_HEADER => server.protocol_version}
        @server_requests = ServerRequests.new(context, @headers)
      end

      def request(method : String, params : Params, options : RequestOptions) : JSON::Any
        exchange(method, JSONValue.with_meta(params, options.meta), @headers, options)
      end

      # List changes arrive unasked in this era, so only resource
      # subscriptions need requests.
      def subscribe(filter : SubscriptionFilter) : Subscription
        filter.resource_uris.each { |uri| exchange("resources/subscribe", uri_params(uri), @headers) }
        Subscription.new(filter) do
          filter.resource_uris.each { |uri| exchange("resources/unsubscribe", uri_params(uri), @headers) }
        end
      end

      # Completes the handshake and switches on what the configuration asks for.
      protected def announce_ready : Nil
        @context.router.notify("notifications/initialized", nil, @headers)
        @context.transport.listen(@headers)
        request_log_level
      end

      protected def handle_request(request : JSONRPC::Request) : Nil
        @server_requests.answer(request)
      end

      protected def cancel_on_server(id : JSONRPC::Id, reason : String?) : Nil
        @context.router.notify("notifications/cancelled", cancelled_params(id, reason), @headers)
        @context.transport.abort(id)
      end

      private def request_log_level
        level = @context.config.log_level
        return unless level && server.capabilities.logging?
        exchange("logging/setLevel", Params{"level" => JSON::Any.new(level)}, @headers)
      end

      private def uri_params(uri : String) : Params
        Params{"uri" => JSON::Any.new(uri)}
      end
    end
  end
end
