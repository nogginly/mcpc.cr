module MCPCProbe
  # The server to probe: one at an HTTP address, or one to launch.
  abstract struct Target
    # How the report names the server.
    abstract def label : String

    abstract def client(config : MCPC::Config) : MCPC::Client
  end

  struct HTTPTarget < Target
    getter url : String
    getter headers : Hash(String, String)

    def initialize(@url : String, @headers = {} of String => String)
    end

    def label : String
      url
    end

    def client(config : MCPC::Config) : MCPC::Client
      MCPC::Client.http(url, headers, config)
    end
  end

  struct StdioTarget < Target
    getter command : String
    getter args : Array(String)

    def initialize(@command : String, @args = [] of String)
    end

    def label : String
      ([command] + args).join(' ')
    end

    def client(config : MCPC::Config) : MCPC::Client
      MCPC::Client.stdio(command, args, config: config)
    end
  end
end
