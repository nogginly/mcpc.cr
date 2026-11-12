module Mcpc
  module Era
    # The `_meta` entries a 2026-07-28 server requires on every request.
    class RequestMeta
      def initialize(version : String, config : Config, capabilities : JSON::Any)
        @entries = Params{
          Protocol::MetaKey::PROTOCOL_VERSION    => JSON::Any.new(version),
          Protocol::MetaKey::CLIENT_INFO         => config.client_info,
          Protocol::MetaKey::CLIENT_CAPABILITIES => capabilities,
        }
        config.log_level.try { |level| @entries[Protocol::MetaKey::LOG_LEVEL] = JSON::Any.new(level) }
      end

      # Returns *params* carrying the required entries and those of *options*.
      def apply(params : Params, options = RequestOptions.new) : Params
        Json.with_meta(params, @entries.merge(options.meta))
      end
    end
  end
end
