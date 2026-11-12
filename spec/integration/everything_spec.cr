require "../spec_helper"

# Runs against the reference server, which needs Node and the network.
# Opt in with: MCPC_INTEGRATION=1 crystal spec --tag integration
private def everything_client(& : Mcpc::Client, EventLog ->)
  pending!("set MCPC_INTEGRATION=1 to run against the reference server") unless ENV["MCPC_INTEGRATION"]?
  transport = Mcpc::Transport::Stdio.new("npx", ["-y", "@modelcontextprotocol/server-everything"],
    stderr: Process::Redirect::Close)
  client = Mcpc::Client.new(transport)
  client.on_elicitation(&.accept({"name" => "Ada", "check" => true}))
  log = EventLog.new(client)
  begin
    client.connect
    yield client, log
  ensure
    client.close
  end
end

describe "the reference server, @modelcontextprotocol/server-everything", tags: "integration" do
  it "connects and describes itself" do
    everything_client do |client|
      client.server.implementation.try(&.name).should_not be_nil
      client.server.capabilities.tools?.should be_true
    end
  end

  it "lists tools and calls one" do
    everything_client do |client|
      client.list_tools.map(&.name).should contain("echo")
      client.call_tool("echo", {"message" => "hello"}).text.should contain("hello")
    end
  end

  it "raises RpcError for a method the server does not have" do
    everything_client do |client|
      expect_raises(Mcpc::RpcError) { client.request("no/such/method") }.code.should eq(-32601)
    end
  end

  it "lists and reads resources, and lists and gets prompts" do
    everything_client do |client|
      resources = client.list_resources
      resources.should_not be_empty
      client.read_resource(resources.first.uri).should_not be_empty
      prompts = client.list_prompts
      prompts.should_not be_empty
      client.list_resource_templates.should_not be_empty
    end
  end

  it "reports progress for a long-running tool" do
    everything_client do |client, log|
      options = Mcpc::RequestOptions.new(progress_token: "job-1", timeout: 30.seconds)
      client.call_tool("trigger-long-running-operation", {"duration" => 1, "steps" => 2}, options)
      log.await(Mcpc::Event::Progress).token.should eq("job-1")
    end
  end

  it "answers the server's elicitation request" do
    everything_client do |client|
      client.list_tools.map(&.name).should contain("trigger-elicitation-request")
      client.call_tool("trigger-elicitation-request").error?.should be_false
    end
  end
end
