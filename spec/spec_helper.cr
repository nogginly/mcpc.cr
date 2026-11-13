require "spec"
require "../src/mcpc"
require "./support/*"

Log.setup(:none)

FIXTURES = Path[__DIR__] / "fixtures" / "2026-07-28"

def fixture(type : String, name : String) : String
  File.read(FIXTURES / type / "#{name}.json")
end

# The example files of one type, or of every type. The pattern uses forward
# slashes because a backslash is an escape character in a glob.
def fixture_paths(type : String = "**") : Array(String)
  Dir.glob((FIXTURES / type / "*.json").to_posix.to_s).sort!
end

# Lets fibers started by the code under test run until *condition* holds.
def wait_until(limit = 2.seconds, & : -> Bool) : Nil
  deadline = Time.instant + limit
  until yield
    raise "condition not met within #{limit}" if Time.instant > deadline
    sleep 1.millisecond
  end
end

def fast_config : MCPC::Config
  MCPC::Config.new.tap do |config|
    config.probe_timeout = 200.milliseconds
    config.request_timeout = 2.seconds
  end
end

def text_result(text : String, error = false)
  {"content" => [{"type" => "text", "text" => text}], "isError" => error}
end

def params_of(message : MCPC::JsonRpc::Request | MCPC::JsonRpc::Notification) : JSON::Any
  message.params || raise "#{message.method} has no params"
end

def result_of(response : MCPC::JsonRpc::Response) : JSON::Any
  response.result || raise "response #{response.id} has no result"
end
