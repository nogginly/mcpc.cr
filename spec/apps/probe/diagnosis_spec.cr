require "./spec_helper"

describe MCPCProbe::Diagnosis do
  it "explains refused credentials and how to pass a token" do
    message = MCPCProbe::Diagnosis.of(MCPC::HTTPError.new(401))
    message.should contain("refused the credentials (HTTP 401)")
    message.should contain("no OAuth")
    message.should contain("--bearer-env")
  end

  it "points at the path for HTTP 404" do
    MCPCProbe::Diagnosis.of(MCPC::HTTPError.new(404)).should contain("Check the path")
  end

  it "reports other HTTP statuses plainly" do
    MCPCProbe::Diagnosis.of(MCPC::HTTPError.new(503)).should eq("The server answered HTTP 503.")
  end

  it "explains a timeout, a version mismatch and an unreachable server" do
    MCPCProbe::Diagnosis.of(MCPC::TimeoutError.new).should eq("The server did not answer in time.")
    MCPCProbe::Diagnosis.of(MCPC::UnsupportedVersionError.new("server speaks 1999-01-01"))
      .should eq("No protocol revision in common: server speaks 1999-01-01.")
    MCPCProbe::Diagnosis.of(MCPC::TransportError.new("cannot start nope")).should contain("could not be reached: cannot start nope")
  end
end
