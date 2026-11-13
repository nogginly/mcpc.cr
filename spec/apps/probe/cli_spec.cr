require "./spec_helper"

# Runs the command and returns its exit status, standard output and standard error.
private def run_probe(*arguments : String, environment = no_environment) : {Int32, String, String}
  run_probe_with(arguments.to_a, environment)
end

private def run_probe_with(arguments : Array(String), environment = no_environment) : {Int32, String, String}
  output = IO::Memory.new
  errors = IO::Memory.new
  status = MCPCProbe::Cli.new(arguments, environment, output, errors).run
  {status, output.to_s, errors.to_s}
end

describe MCPCProbe::Cli do
  it "probes an HTTP server and exits 0" do
    HttpFakeServer.open(well_stocked_server) do |http|
      status, output, errors = run_probe("--timeout", "2", http.url)

      status.should eq(0)
      output.should contain("Result    connected\n")
      output.should contain("Tools (1)")
      errors.should be_empty
    end
  end

  it "names itself to the server" do
    server = well_stocked_server
    HttpFakeServer.open(server) do |http|
      run_probe(http.url)
      params_of(server.last_request("initialize"))["clientInfo"]["name"].should eq("mcpc-probe")
    end
  end

  it "sends credentials taken from the environment" do
    HttpFakeServer.open(well_stocked_server) do |http|
      run_probe("--bearer-env", "TOKEN", http.url, environment: {"TOKEN" => "s3cret"})
      http.headers_for("tools/list")["Authorization"].should eq("Bearer s3cret")
    end
  end

  it "reports as JSON when asked" do
    HttpFakeServer.open(well_stocked_server) do |http|
      status, output, _ = run_probe("--json", http.url)
      status.should eq(0)
      JSON.parse(output)["ok"].should be_true
    end
  end

  it "exits 1 and explains when the server refuses the credentials" do
    server = FakeServer.new
    server.fail_with("server/discover", -32600, "Unauthorized")
    HttpFakeServer.open(server) do |http|
      http.error_statuses[-32600] = 401
      status, output, _ = run_probe(http.url)

      status.should eq(1)
      output.should contain("FAILED. The server refused the credentials (HTTP 401)")
    end
  end

  it "exits 1 when an advertised list cannot be read" do
    server = well_stocked_server
    server.fail_with("tools/list", -32603, "boom")
    HttpFakeServer.open(server) do |http|
      run_probe(http.url)[0].should eq(1)
    end
  end

  it "exits 1 when a server command cannot be started" do
    status, output, _ = run_probe("--", "/no/such/mcp-server")
    status.should eq(1)
    output.should contain("FAILED. The server could not be reached")
  end

  it "exits 2 and writes to standard error for a bad command line" do
    status, output, errors = run_probe_with([] of String)
    status.should eq(2)
    output.should be_empty
    errors.should contain("Name a server")
    errors.should contain("mcpc-probe --help")
  end

  it "shows help and the version without probing anything" do
    run_probe("--help").should eq({0, MCPCProbe::Options.new(["--help"], no_environment).usage + "\n", ""})
    run_probe("--version").should eq({0, "mcpc-probe #{MCPC::VERSION}\n", ""})
  end
end
