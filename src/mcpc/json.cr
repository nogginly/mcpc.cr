module Mcpc
  # The `params` object of a JSON-RPC message.
  alias Params = Hash(String, JSON::Any)

  # Conversions between application values and `JSON::Any`.
  module Json
    # Returns *value* as `JSON::Any`; accepts anything that responds to `to_json`.
    def self.any(value) : JSON::Any
      value.is_a?(JSON::Any) ? value : JSON.parse(value.to_json)
    end

    # Returns *params* with *additions* merged into its `_meta` object.
    # An empty *additions* leaves *params* untouched.
    def self.with_meta(params : Params, additions : Params) : Params
      return params if additions.empty?
      meta = params["_meta"]?.try(&.as_h?) || Params.new
      params.merge({"_meta" => JSON::Any.new(meta.merge(additions))})
    end
  end
end
