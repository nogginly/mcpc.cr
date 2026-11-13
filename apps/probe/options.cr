module McpcProbe
  # The command line asked for something that cannot be done.
  class UsageError < Exception
  end

  # What the command line asked for.
  class Options
    USAGE = <<-TEXT
      Usage: #{NAME} [options] URL
             #{NAME} [options] -- COMMAND [ARGS...]

      Connects to an MCP server and reports what it advertises.
      Exits 0 when everything advertised could be read, 1 otherwise.

      TEXT

    getter target : Target?
    getter timeout : Time::Span = 30.seconds
    getter? json = false
    getter? help = false
    getter? version = false
    getter usage : String = ""

    # Reads *arguments*, taking header values named by `--header-env` and
    # `--bearer-env` from *environment*. Raises `UsageError` on a bad command line.
    def initialize(arguments : Array(String), @environment : Hash(String, String))
      @headers = {} of String => String
      parse(arguments)
    end

    private def parse(arguments : Array(String))
      words = [] of String
      parser = build_parser(words)
      parser.parse(arguments.dup)
      @usage = parser.to_s
      @target = target_from(words) unless help? || version?
    rescue error : OptionParser::Exception
      raise UsageError.new("#{error.message}. Put a server command after `--`.")
    end

    private def build_parser(words : Array(String)) : OptionParser
      OptionParser.new do |parser|
        parser.banner = USAGE
        parser.on("-H HEADER", "--header HEADER", "Send an HTTP header, as \"Name: value\"") { |text| add_header(text, ':') }
        parser.on("--header-env NAME=VAR", "Send header NAME with the value of environment variable VAR") do |text|
          name, variable = split(text, '=')
          @headers[name] = from_environment(variable)
        end
        parser.on("--bearer-env VAR", "Send \"Authorization: Bearer\" with the token in VAR") do |variable|
          @headers["Authorization"] = "Bearer #{from_environment(variable)}"
        end
        parser.on("--timeout SECONDS", "Give up on a request after this long (default 30)") { |text| @timeout = seconds(text) }
        parser.on("--json", "Report as JSON") { @json = true }
        parser.on("-v", "--version", "Show the version") { @version = true }
        parser.on("-h", "--help", "Show this help") { @help = true }
        parser.unknown_args { |before_dash, after_dash| words.concat(before_dash).concat(after_dash) }
      end
    end

    private def target_from(words : Array(String)) : Target
      first = words.first? || raise UsageError.new("Name a server: a URL, or a command after `--`.")
      return StdioTarget.new(first, words[1..]) unless first.matches?(/\Ahttps?:\/\//)
      raise UsageError.new("Give one URL only.") if words.size > 1
      HttpTarget.new(first, @headers)
    end

    private def add_header(text : String, separator : Char)
      name, value = split(text, separator)
      @headers[name] = value
    end

    private def split(text : String, separator : Char) : {String, String}
      name, found, value = text.partition(separator)
      raise UsageError.new("Expected NAME#{separator}VALUE but got #{text.inspect}.") if found.empty? || name.blank?
      {name.strip, value.strip}
    end

    private def from_environment(variable : String) : String
      @environment[variable]? || raise UsageError.new("Environment variable #{variable} is not set.")
    end

    private def seconds(text : String) : Time::Span
      number = text.to_f? || 0.0
      raise UsageError.new("Timeout must be a positive number of seconds.") unless number > 0
      number.seconds
    end
  end
end
