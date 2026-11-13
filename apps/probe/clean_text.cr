module McpcProbe
  # Makes text written by a server safe to print on a terminal.
  module CleanText
    # Returns the first line of *text* without control characters, cut to *limit*.
    def self.line(text : String, limit : Int32 = 80) : String
      line = strip_controls(text.lines.first? || "")
      line.size > limit ? "#{line[0, limit - 1]}…" : line
    end

    # Returns every line of *text* without control characters.
    def self.block(text : String) : Array(String)
      text.lines.map { |line| strip_controls(line) }
    end

    private def self.strip_controls(text : String) : String
      text.gsub { |char| char.control? ? ' ' : char }.strip
    end
  end
end
