module MCPC
  # Per-request choices. Every field is optional.
  #
  # * `timeout` overrides `Config#request_timeout`.
  # * `progress_token` asks the server for `Event::Progress` events carrying that token.
  # * `cancellation` lets another fiber abandon the request.
  struct RequestOptions
    getter timeout : Time::Span?
    getter progress_token : String?
    getter cancellation : Cancellation?

    def initialize(@timeout = nil, @progress_token = nil, @cancellation = nil)
    end

    # The `_meta` entries these options add to a request.
    def meta : Params
      meta = Params.new
      progress_token.try { |token| meta[Protocol::MetaKey::PROGRESS_TOKEN] = JSON::Any.new(token) }
      meta
    end
  end
end
