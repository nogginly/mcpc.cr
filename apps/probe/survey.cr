module MCPCProbe
  # Connects a client and collects everything the server advertises.
  class Survey
    def initialize(@client : MCPC::Client, @target : String)
    end

    # Never raises for a server's failings: they are recorded in the report.
    def run : Report
      report = Report.new(@target)
      connect_and_collect(report)
      report
    ensure
      @client.close
    end

    private def connect_and_collect(report : Report)
      report.server = server = @client.connect
      collect_lists(report, server.capabilities)
    rescue error : MCPC::Error
      report.failure = Diagnosis.of(error)
    end

    private def collect_lists(report : Report, capabilities : MCPC::ServerCapabilities)
      if capabilities.tools?
        report.sections << section("Tools") { @client.list_tools.map { |tool| Item.new(tool.name, tool.description) } }
      end
      if capabilities.resources?
        report.sections << section("Resources") do
          @client.list_resources.map { |resource| Item.new(resource.uri, resource.description || resource.name) }
        end
        report.sections << section("Resource templates") do
          @client.list_resource_templates.map { |template| Item.new(template.uri_template, template.description || template.name) }
        end
      end
      if capabilities.prompts?
        report.sections << section("Prompts") { @client.list_prompts.map { |prompt| Item.new(prompt.name, prompt.description) } }
      end
    end

    private def section(title : String, & : -> Array(Item)) : Section
      Section.new(title, yield)
    rescue error : MCPC::Error
      Section.new(title, error: Diagnosis.of(error))
    end
  end
end
