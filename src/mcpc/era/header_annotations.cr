module MCPC
  module Era
    # The `x-mcp-header` annotations of one tool's input schema: which
    # arguments a server wants mirrored into `Mcp-Param-*` headers.
    class HeaderAnnotations
      KEYWORD        = "x-mcp-header"
      HEADER_TOKEN   = /\A[!#$%&'*+\-.^_`|~0-9A-Za-z]+\z/
      MIRRORED_TYPES = {"string", "integer", "boolean"}

      # The annotations break a rule of the specification.
      class Invalid < MCPC::ProtocolError
      end

      # Maps the property path of each annotated argument to its header name suffix.
      getter headers_by_path = {} of Array(String) => String

      # Raises `Invalid` when any annotation in *schema* is not allowed.
      def initialize(schema : JSON::Any)
        collect(schema, [] of String)
        raise Invalid.new("#{KEYWORD} used outside a chain of properties") if misplaced?(schema)
        raise Invalid.new("#{KEYWORD} names are not unique") if duplicates?
      end

      # Returns the headers that mirror *arguments*; absent, null and
      # non-primitive values produce none.
      def mirror(arguments : JSON::Any?) : Transport::Headers
        headers = Transport::Headers.new
        headers_by_path.each do |path, name|
          text = value_at(arguments, path).try { |value| header_text(value) }
          headers["Mcp-Param-#{name}"] = HeaderValue.encode(text) if text
        end
        headers
      end

      private def value_at(arguments : JSON::Any?, path : Array(String)) : JSON::Any?
        path.reduce(arguments) { |node, key| node.try(&.as_h?).try(&.[key]?) }
      end

      private def collect(schema : JSON::Any, path : Array(String))
        properties = schema.as_h?.try(&.["properties"]?).try(&.as_h?) || return
        properties.each do |name, property|
          property_path = path + [name]
          property.as_h?.try(&.[KEYWORD]?).try { |header| headers_by_path[property_path] = valid_name(header, property) }
          collect(property, property_path)
        end
      end

      private def valid_name(header : JSON::Any, property : JSON::Any) : String
        name = header.as_s? || ""
        raise Invalid.new("#{KEYWORD} #{header.to_json} is not a header token") unless HEADER_TOKEN.matches?(name)
        type = property["type"]?.try(&.as_s?)
        raise Invalid.new("#{KEYWORD} #{name} is on a #{type || "untyped"} property") unless MIRRORED_TYPES.includes?(type)
        name
      end

      private def misplaced?(schema : JSON::Any) : Bool
        count_keyword(schema) > headers_by_path.size
      end

      private def count_keyword(node : JSON::Any) : Int32
        if object = node.as_h?
          object.sum { |key, value| (key == KEYWORD && !value.as_h? ? 1 : 0) + count_keyword(value) }
        elsif array = node.as_a?
          array.sum { |item| count_keyword(item) }
        else
          0
        end
      end

      private def duplicates? : Bool
        names = headers_by_path.values.map(&.downcase)
        names.uniq.size < names.size
      end

      private def header_text(value : JSON::Any) : String?
        case raw = value.raw
        when String, Int64, Bool then raw.to_s
        end
      end
    end
  end
end
