module MCPCProbe
  # Writes a report for a program to read.
  class JsonRenderer
    def initialize(@io : IO)
    end

    def render(report : Report) : Nil
      JSON.build(@io, indent: 2) do |json|
        json.object do
          json.field "target", report.target
          json.field "ok", report.ok?
          json.field "failure", report.failure
          report.server.try { |server| server_fields(json, server) }
          json.field "sections" do
            json.array { report.sections.each { |section| section_object(json, section) } }
          end
        end
      end
      @io.puts
    end

    private def server_fields(json : JSON::Builder, server : MCPC::ServerInfo)
      json.field "protocolVersion", server.protocol_version
      json.field "stateless", server.stateless?
      json.field "serverName", server.implementation.try(&.name)
      json.field "serverVersion", server.implementation.try(&.version)
      json.field "capabilities", server.capabilities.raw
      json.field "instructions", server.instructions
    end

    private def section_object(json : JSON::Builder, section : Section)
      json.object do
        json.field "title", section.title
        json.field "error", section.error
        json.field "items" do
          json.array do
            section.items.each do |item|
              json.object do
                json.field "name", item.name
                json.field "description", item.description
              end
            end
          end
        end
      end
    end
  end
end
