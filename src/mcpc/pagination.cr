module Mcpc
  # Follows a paginated list to its end.
  module Pagination
    # Yields nil, then each cursor the server hands back, and returns the
    # items found under *key* in every page.
    def self.collect(key : String, type : T.class, & : String? -> JSON::Any) : Array(T) forall T
      items = [] of T
      cursor = nil
      loop do
        page = yield cursor
        items.concat(Array(T).from_json(page[key].to_json))
        next_cursor = page["nextCursor"]?.try(&.as_s?)
        return items unless next_cursor
        raise ProtocolError.new("server repeated cursor #{next_cursor}") if next_cursor == cursor
        cursor = next_cursor
      end
    end
  end
end
