# mcpc.cr

An MCP client as a Crystal shard. It talks to [Model Context Protocol](https://modelcontextprotocol.io)
servers over stdio or Streamable HTTP, and hides which revision of the protocol the server speaks.

Think of it as a travel adaptor: your app has one plug, and the shard works out which socket is in the wall.

## Install

Add the shard to `shard.yml`, then run `shards install`.

```yaml
dependencies:
  mcpc:
    github: nogginly/mcpc.cr
```

It needs Crystal 1.20 or later and nothing beyond the standard library. It is tested on Linux,
macOS and Windows.

## Quick start

```crystal
require "mcpc"

client = MCPC::Client.stdio("npx", ["-y", "@modelcontextprotocol/server-everything"])
client.connect

client.list_tools.each { |tool| puts tool.name }

result = client.call_tool("echo", {"message" => "hello"})
puts result.text

client.close
```

For a remote server, swap the first line. The rest stays the same.

```crystal
client = MCPC::Client.http("https://example.com/mcp", {"Authorization" => "Bearer #{token}"})
```

A runnable version is in [`samples/everything.cr`](samples/everything.cr).

## How a session goes

```mermaid
flowchart TD
    A[Client.stdio or Client.http] --> B[on_event / on_elicitation]
    B --> C[connect]
    C --> D{{Server answers server/discover?}}
    D -- yes --> E[Stateless era, 2026-07-28]
    D -- no --> F[Handshake era, 2025-11-25 and older]
    E --> G[list, call, read, subscribe]
    F --> G
    G --> H[close]
    style E stroke:#2a9d4f,stroke-width:3px
```

`connect` returns a `ServerInfo`: the revision in use, the server's name, its capabilities and its
instructions. Your code is the same on both branches.

## What you can ask a server

| Method | Returns |
|---|---|
| `list_tools` | `Array(Tool)`, every page |
| `call_tool(name, arguments)` | `CallToolResult` |
| `list_resources` | `Array(Resource)` |
| `list_resource_templates` | `Array(ResourceTemplate)` |
| `read_resource(uri)` | `Array(ResourceContents)` |
| `list_prompts` | `Array(Prompt)` |
| `get_prompt(name, arguments)` | `PromptResult` |
| `subscribe(filter)` | `Subscription` |
| `request(method, params)` | raw `JSON::Any`, for anything not listed above |

Each call blocks the calling fiber until the answer arrives. Run calls in separate fibers to make
them concurrent.

### Tool results

A tool that fails is not an exception. It returns a result with `error?` set, so a model can read
the reason and try again.

```crystal
result = client.call_tool("get_weather", {"city" => "Atlantis"})
if result.error?
  puts "tool failed: #{result.text}"
else
  result.content.each do |block|
    case block
    when MCPC::TextContent      then puts block.text
    when MCPC::ImageContent     then save(block.data, block.mime_type)
    when MCPC::ResourceLink     then puts "see #{block.uri}"
    when MCPC::EmbeddedResource then puts block.resource.text
    end
  end
  puts result.structured_content
end
```

## Events

Register one handler. It receives everything the server or the connection reports unasked.

```crystal
client.on_event do |event|
  case event
  when MCPC::Event::Progress           then puts "#{event.token}: #{event.progress} of #{event.total}"
  when MCPC::Event::LogMessage         then puts "[#{event.level}] #{event.data}"
  when MCPC::Event::ToolsChanged       then tools = client.list_tools
  when MCPC::Event::PromptsChanged     then prompts = client.list_prompts
  when MCPC::Event::ResourcesChanged   then resources = client.list_resources
  when MCPC::Event::ResourceUpdated    then client.read_resource(event.uri)
  when MCPC::Event::SubscriptionClosed then puts "subscription ended: #{event.reason}"
  when MCPC::Event::Disconnected       then puts "connection lost: #{event.reason}"
  end
end
```

Events arrive in order on a fiber of their own, so the handler may call the client, as above.

## Per-request options

```crystal
cancellation = MCPC::Cancellation.new
options = MCPC::RequestOptions.new(
  timeout: 30.seconds,        # instead of Config#request_timeout
  progress_token: "import-1", # ask for Event::Progress carrying this token
  cancellation: cancellation, # lets another fiber give up on the call
)

spawn { client.call_tool("import", {"file" => "big.csv"}, options) }
cancellation.cancel("user pressed stop")   # the call raises MCPC::CancelledError
```

A call that times out or is cancelled is also cancelled on the server.

## Answering a server's questions

A tool may need something from the user halfway through, such as a confirmation. Register a handler
**before** `connect`; servers are told the client can answer only if one exists by then.

```crystal
client.on_elicitation do |request|
  puts request.message              # written by the server: untrusted
  puts request.requested_schema     # JSON Schema of the fields wanted
  request.accept({"guests" => 4})   # or request.decline, or request.cancel
end
```

The two protocol eras ask in different ways. The handler is the same for both.

## Change notifications

```crystal
filter = MCPC::SubscriptionFilter.new(tools: true, resource_uris: ["file:///notes/todo.md"])
subscription = client.subscribe(filter)
subscription.filter   # what the server agreed to send
# ... Event::ToolsChanged and Event::ResourceUpdated now arrive at on_event ...
subscription.close
```

Handshake-era servers send list changes without being asked, so you may see those events before
subscribing.

## Errors

Everything raised is an `MCPC::Error`.

| Error | Meaning |
|---|---|
| `RPCError` | The server refused the request. Has `code` and `data`. |
| `TimeoutError` | No answer in time. |
| `CancelledError` | Your `Cancellation` was cancelled. |
| `InputRequiredError` | The server wants input and there is no handler, or it kept asking. |
| `ProtocolError` | The server sent something malformed. |
| `UnsupportedVersionError` | Client and server share no protocol revision. |
| `TransportError` | The server could not be reached. |
| `ConnectionClosedError` | The connection ended mid-request. A `TransportError`. |
| `HTTPError` | An HTTP refusal such as 401. Has `status` and `body`. A `TransportError`. |
| `SessionExpiredError` | The HTTP session is gone; make a new client. An `HTTPError`. |
| `NotConnectedError` | Called before `connect` or after `close`. |

## Configuration

```crystal
config = MCPC::Config.new
config.client_name = "my-app"
config.client_version = "1.2.0"
config.request_timeout = 20.seconds  # default 60 s
config.probe_timeout = 2.seconds     # default 5 s; see below
config.max_input_rounds = 4          # default 8
config.log_level = "warning"         # ask for Event::LogMessage at this level and above

client = MCPC::Client.stdio("my-server", config: config)
```

`probe_timeout` is how long `connect` waits for an older server to react to the modern greeting
before falling back. A stdio server that ignores unknown requests costs you that long, once.

To send a stdio server's stderr somewhere other than your own, build the transport yourself:

```crystal
transport = MCPC::Transport::Stdio.new("my-server", stderr: File.open("server.log", "a"))
client = MCPC::Client.new(transport)
```

## Checking a server: `mcpc-probe`

The shard comes with a command-line tool that connects to a server and reports what it
advertises. Use it to find out whether a server works with this client before writing any code.

```sh
shards build
bin/mcpc-probe https://example.com/mcp
bin/mcpc-probe -- npx -y @modelcontextprotocol/server-everything
```

```text
Target    npx -y @modelcontextprotocol/server-everything
Result    connected
Server    mcp-servers/everything 1.0.0
Protocol  2025-11-25 (handshake era)

Capabilities
  tools                        {"listChanged":true}
  prompts                      {"listChanged":true}
  ...

Tools (13)
  echo                         Echoes back the input string
  get-sum                      Returns the sum of two numbers
  ...
```

It also lists resources, resource templates and prompts, and prints the server's instructions.

| Option | Does |
|---|---|
| `-H`, `--header "Name: value"` | Sends an HTTP header |
| `--header-env NAME=VAR` | Sends header `NAME` with the value of environment variable `VAR` |
| `--bearer-env VAR` | Sends `Authorization: Bearer` with the token in `VAR` |
| `--timeout SECONDS` | Gives up on a request after this long; default 30 |
| `--json` | Reports as JSON, for scripts |

Prefer the `-env` options for secrets: a value typed on the command line is visible to other
processes and lands in your shell history.

```sh
MY_TOKEN=... bin/mcpc-probe --bearer-env MY_TOKEN https://example.com/mcp
```

| Exit status | Meaning |
|---|---|
| 0 | Connected, and everything the server advertises could be read |
| 1 | Could not connect, or an advertised list could not be read |
| 2 | The command line was wrong |

1. Put a server command after `--`, so that its flags are not taken for the probe's own.
2. A server that requires the OAuth flow will be reported as refusing the credentials. The shard
   has no OAuth yet; a static token or API key works.
3. From a project that depends on the shard, build the probe with
   `crystal build lib/mcpc/apps/probe/main.cr -o bin/mcpc-probe`.

## Windows

A server started through a batch file, such as `npx`, must be launched through the command
interpreter, because Windows cannot run a batch file directly.

```crystal
client = MCPC::Client.stdio("cmd.exe", ["/c", "npx", "-y", "@modelcontextprotocol/server-everything"])
```

```sh
bin\mcpc-probe -- cmd.exe /c npx -y @modelcontextprotocol/server-everything
```

## Trust

Tool descriptions, prompts, annotations, `ServerInfo#instructions` and elicitation messages are
written by the server. Show them or pass them to a model as untrusted input. The shard never acts
on them.

## What it covers

| | |
|---|---|
| Protocol revisions | 2026-07-28 (stateless), and 2025-11-25, 2025-06-18, 2025-03-26, 2024-11-05 (handshake) |
| Transports | stdio, Streamable HTTP |
| Server features | tools, resources, resource templates, prompts, logging, progress, cancellation, subscriptions |
| Client features | form-mode elicitation |

Not built yet: OAuth, the deprecated HTTP+SSE transport, sampling, roots, URL-mode elicitation and
the tasks extension. [DESIGN.md](DESIGN.md) lists the rest and says why.

## More

- [DESIGN.md](DESIGN.md): how it works inside.
- [DEVELOPMENT.md](DEVELOPMENT.md): building, testing and contributing.
