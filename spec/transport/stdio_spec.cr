require "../spec_helper"

private NO_HEADERS = MCPC::Transport::Headers.new

private def shell_transport(script : String, grace = 2.seconds) : MCPC::Transport::Stdio
  MCPC::Transport::Stdio.new("sh", ["-c", script], stderr: Process::Redirect::Close, shutdown_grace: grace)
end

private def collect_messages(transport : MCPC::Transport) : Array(MCPC::JSONRPC::Message)
  messages = [] of MCPC::JSONRPC::Message
  transport.on_message { |message| messages << message }
  messages
end

describe MCPC::Transport::Stdio do
  it "writes one compact JSON line per message and reads replies line by line" do
    transport = shell_transport("cat")
    received = collect_messages(transport)
    transport.open

    transport.send(MCPC::JSONRPC::Notification.new("first", JSON.parse(%({"text":"a\\nb"}))), NO_HEADERS)
    transport.send(MCPC::JSONRPC::Notification.new("second"), NO_HEADERS)

    wait_until { received.size == 2 }
    received.map(&.as(MCPC::JSONRPC::Notification).method).should eq(["first", "second"])
    received.first.as(MCPC::JSONRPC::Notification).params.should eq(JSON.parse(%({"text":"a\\nb"})))
  ensure
    transport.try(&.close)
  end

  it "skips output that is not JSON-RPC" do
    script = %q(echo 'Starting server...'; echo; echo '{"jsonrpc":"2.0","method":"ready"}'; cat >/dev/null)
    transport = shell_transport(script)
    received = collect_messages(transport)
    transport.open

    wait_until { received.size == 1 }
    received.first.as(MCPC::JSONRPC::Notification).method.should eq("ready")
  ensure
    transport.try(&.close)
  end

  it "reports when the server exits" do
    transport = shell_transport("exit 0")
    closes = 0
    transport.on_close { closes += 1 }
    transport.open

    wait_until { closes == 1 }
  ensure
    transport.try(&.close)
  end

  it "raises ConnectionClosedError when sending to a server that has gone" do
    transport = shell_transport("exit 0")
    closed = false
    transport.on_close { closed = true }
    transport.open
    wait_until { closed }
    sleep 50.milliseconds

    expect_raises(MCPC::ConnectionClosedError) do
      3.times { transport.send(MCPC::JSONRPC::Notification.new("late"), NO_HEADERS) }
    end
  ensure
    transport.try(&.close)
  end

  it "raises TransportError when the command cannot be started" do
    transport = MCPC::Transport::Stdio.new("/no/such/mcp-server")
    expect_raises(MCPC::TransportError, "cannot start") { transport.open }
  end

  it "refuses to send before it is opened" do
    expect_raises(MCPC::ConnectionClosedError) do
      shell_transport("cat").send(MCPC::JSONRPC::Notification.new("early"), NO_HEADERS)
    end
  end

  it "ends a well-behaved server by closing its input" do
    transport = shell_transport("cat")
    closed = false
    transport.on_close { closed = true }
    transport.open

    transport.close
    wait_until { closed }
  end

  it "forces out a server that ignores both end of input and SIGTERM" do
    transport = shell_transport(%q(trap '' TERM; while true; do sleep 1; done), grace: 100.milliseconds)
    transport.open
    sleep 100.milliseconds

    started = Time.instant
    transport.close
    (Time.instant - started).should be < 2.seconds
  end

  it "does not offer transport-level cancellation or headers" do
    transport = shell_transport("cat")
    transport.abort(1_i64).should be_false
    transport.uses_headers?.should be_false
  end
end
