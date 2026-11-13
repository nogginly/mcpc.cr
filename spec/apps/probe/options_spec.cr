require "./spec_helper"

private def options(*arguments : String, environment = no_environment) : McpcProbe::Options
  McpcProbe::Options.new(arguments.to_a, environment)
end

private def http_target(*arguments : String, environment = no_environment) : McpcProbe::HttpTarget
  options(*arguments, environment: environment).target.as(McpcProbe::HttpTarget)
end

describe McpcProbe::Options do
  it "takes a URL as an HTTP target" do
    target = http_target("https://example.com/mcp")
    target.url.should eq("https://example.com/mcp")
    target.headers.should be_empty
    target.label.should eq("https://example.com/mcp")
  end

  it "takes everything after -- as a command, flags included" do
    target = options("--json", "--", "npx", "-y", "some-server").target.as(McpcProbe::StdioTarget)
    target.command.should eq("npx")
    target.args.should eq(["-y", "some-server"])
    target.label.should eq("npx -y some-server")
  end

  it "takes plain words as a command without --" do
    target = options("my-server", "serve").target.as(McpcProbe::StdioTarget)
    target.command.should eq("my-server")
    target.args.should eq(["serve"])
  end

  it "reads headers given on the command line" do
    http_target("-H", "X-Api-Key: abc", "--header", "X-Team:core", "https://example.com/mcp").headers
      .should eq({"X-Api-Key" => "abc", "X-Team" => "core"})
  end

  it "keeps colons inside a header's value" do
    http_target("-H", "Referer: https://a.example/x", "https://example.com/mcp").headers["Referer"].should eq("https://a.example/x")
  end

  it "reads a header's value from the environment" do
    http_target("--header-env", "X-Api-Key=MY_KEY", "https://example.com/mcp", environment: {"MY_KEY" => "s3cret"}).headers
      .should eq({"X-Api-Key" => "s3cret"})
  end

  it "builds a bearer header from a token in the environment" do
    http_target("--bearer-env", "TOKEN", "https://example.com/mcp", environment: {"TOKEN" => "abc"}).headers
      .should eq({"Authorization" => "Bearer abc"})
  end

  it "defaults to text output and a 30 second timeout" do
    chosen = options("https://example.com/mcp")
    chosen.json?.should be_false
    chosen.timeout.should eq(30.seconds)
  end

  it "reads --json and --timeout" do
    chosen = options("--json", "--timeout", "2.5", "https://example.com/mcp")
    chosen.json?.should be_true
    chosen.timeout.should eq(2.5.seconds)
  end

  it "needs no target for --help or --version" do
    options("--help").help?.should be_true
    options("--help").usage.should contain("Usage: mcpc-probe")
    options("-v").version?.should be_true
  end

  {
    "no server"                     => [] of String,
    "two URLs"                      => ["https://a.example/mcp", "https://b.example/mcp"],
    "a header without a colon"      => ["-H", "nonsense", "https://example.com/mcp"],
    "a header without a name"       => ["-H", ": value", "https://example.com/mcp"],
    "an unset environment variable" => ["--bearer-env", "MISSING", "https://example.com/mcp"],
    "a malformed --header-env"      => ["--header-env", "X-Api-Key", "https://example.com/mcp"],
    "a timeout that is no number"   => ["--timeout", "soon", "https://example.com/mcp"],
    "a timeout of zero"             => ["--timeout", "0", "https://example.com/mcp"],
    "an unknown flag"               => ["--frobnicate", "https://example.com/mcp"],
    "a server flag before --"       => ["npx", "-y", "some-server"],
  }.each do |fault, arguments|
    it "rejects #{fault}" do
      expect_raises(McpcProbe::UsageError) { McpcProbe::Options.new(arguments, no_environment) }
    end
  end

  it "suggests -- when a server's flag is mistaken for its own" do
    expect_raises(McpcProbe::UsageError, "after `--`") { options("npx", "-y", "some-server") }
  end
end
