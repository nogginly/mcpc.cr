module McpcProbe
  # Writes a report for a person to read.
  class TextRenderer
    NAME_WIDTH =  28
    NAME_LIMIT = 200

    def initialize(@io : IO)
    end

    def render(report : Report) : Nil
      field("Target", report.target)
      server = report.server
      return field("Result", "FAILED. #{report.failure}") unless server
      field("Result", report.ok? ? "connected" : "connected, with problems")
      describe(server)
      report.sections.each { |section| list(section) }
      instructions(server)
    end

    private def describe(server : Mcpc::ServerInfo)
      server.implementation.try { |program| field("Server", CleanText.line("#{program.name} #{program.version}")) }
      era = server.stateless? ? "stateless" : "handshake"
      field("Protocol", "#{server.protocol_version} (#{era} era)")
      heading("Capabilities")
      capabilities = server.capabilities.raw.as_h? || {} of String => JSON::Any
      @io.puts "  none advertised" if capabilities.empty?
      capabilities.each { |name, settings| row(name, settings.to_json) }
    end

    private def list(section : Section)
      heading(section.error ? section.title : "#{section.title} (#{section.items.size})")
      section.error.try { |error| return @io.puts "  FAILED. #{error}" }
      section.items.each { |item| row(item.name, item.description || "") }
    end

    private def instructions(server : Mcpc::ServerInfo)
      text = server.instructions || return
      heading("Instructions (written by the server)")
      CleanText.block(text).each { |line| @io.puts "  #{line}".rstrip }
    end

    private def field(name : String, value : String)
      @io.puts "#{name.ljust(10)}#{value}"
    end

    private def heading(text : String)
      @io.puts
      @io.puts text
    end

    private def row(name : String, detail : String)
      @io.puts "  #{CleanText.line(name, NAME_LIMIT).ljust(NAME_WIDTH)} #{CleanText.line(detail)}".rstrip
    end
  end
end
