module MCPCProbe
  # Runs the command: reads the options, probes the server, prints the report.
  class CLI
    EXIT_OK      = 0
    EXIT_PROBLEM = 1
    EXIT_USAGE   = 2

    def initialize(@arguments : Array(String), @environment : Hash(String, String),
                   @output : IO = STDOUT, @errors : IO = STDERR)
    end

    # Returns the process exit status.
    def run : Int32
      options = Options.new(@arguments, @environment)
      return show(options.usage) if options.help?
      return show("#{NAME} #{MCPC::VERSION}") if options.version?
      target = options.target || raise UsageError.new("Name a server.")
      report = Survey.new(target.client(config(options)), target.label).run
      renderer(options).render(report)
      report.ok? ? EXIT_OK : EXIT_PROBLEM
    rescue error : UsageError
      @errors.puts error.message
      @errors.puts "Try `#{NAME} --help`."
      EXIT_USAGE
    end

    private def show(text : String) : Int32
      @output.puts text
      EXIT_OK
    end

    private def config(options : Options) : MCPC::Config
      MCPC::Config.new.tap do |config|
        config.client_name = NAME
        config.request_timeout = options.timeout
      end
    end

    private def renderer(options : Options) : TextRenderer | JSONRenderer
      options.json? ? JSONRenderer.new(@output) : TextRenderer.new(@output)
    end
  end
end
