require "base64"

module Mcpc
  module Era
    # Encodes text for an `Mcp-Name` or `Mcp-Param-*` header.
    module HeaderValue
      PREFIX = "=?base64?"
      SUFFIX = "?="

      # Returns *text* unchanged when it is safe as a header value, and
      # wrapped in the base64 sentinel otherwise.
      def self.encode(text : String) : String
        plain?(text) ? text : "#{PREFIX}#{Base64.strict_encode(text)}#{SUFFIX}"
      end

      private def self.plain?(text : String) : Bool
        text.each_char.all? { |char| char == ' ' || char == '\t' || ('!'..'~').includes?(char) } &&
          text == text.strip &&
          !(text.starts_with?(PREFIX) && text.ends_with?(SUFFIX))
      end
    end
  end
end
