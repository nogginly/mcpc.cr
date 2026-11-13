require "../spec_helper"

private def envelope_fixtures : Array(String)
  fixture_paths.select { |path| JSON.parse(File.read(path)).as_h?.try(&.has_key?("jsonrpc")) }
end

describe MCPC::JsonRpc do
  describe ".parse" do
    it "round-trips every JSON-RPC example of the specification unchanged" do
      paths = envelope_fixtures
      paths.size.should be > 25
      paths.each do |path|
        original = File.read(path)
        JSON.parse(MCPC::JsonRpc.parse(original).to_json).should eq(JSON.parse(original)), failure_message: path
      end
    end

    it "reads a message with a method and an id as a request" do
      message = MCPC::JsonRpc.parse(%({"jsonrpc":"2.0","id":7,"method":"tools/list","params":{}}))
      message.should be_a(MCPC::JsonRpc::Request)
      message.as(MCPC::JsonRpc::Request).method.should eq("tools/list")
    end

    it "reads a message with a method and no id as a notification" do
      MCPC::JsonRpc.parse(%({"jsonrpc":"2.0","method":"notifications/initialized"}))
        .should be_a(MCPC::JsonRpc::Notification)
    end

    it "reads a result as a response" do
      message = MCPC::JsonRpc.parse(%({"jsonrpc":"2.0","id":1,"result":{"tools":[]}}))
      message.as(MCPC::JsonRpc::Response).result.should eq(JSON.parse(%({"tools":[]})))
    end

    it "reads an error as a response, even without an id" do
      message = MCPC::JsonRpc.parse(%({"jsonrpc":"2.0","error":{"code":-32700,"message":"Parse error"}}))
      response = message.as(MCPC::JsonRpc::Response)
      response.id.should be_nil
      response.error.try(&.code).should eq(-32700)
    end

    it "keeps the type of an id" do
      MCPC::JsonRpc.parse(%({"jsonrpc":"2.0","id":"abc","method":"x"})).as(MCPC::JsonRpc::Request).id.should eq("abc")
      MCPC::JsonRpc.parse(%({"jsonrpc":"2.0","id":12,"method":"x"})).as(MCPC::JsonRpc::Request).id.should eq(12_i64)
    end

    it "rejects text that is not JSON" do
      expect_raises(MCPC::JsonRpc::InvalidMessage) { MCPC::JsonRpc.parse("Starting server...") }
    end

    it "rejects a batch" do
      expect_raises(MCPC::JsonRpc::InvalidMessage) { MCPC::JsonRpc.parse(%([{"jsonrpc":"2.0","method":"x"}])) }
    end

    it "rejects an object that is no kind of message" do
      expect_raises(MCPC::JsonRpc::InvalidMessage) { MCPC::JsonRpc.parse(%({"jsonrpc":"2.0","id":1})) }
    end
  end

  it "writes compact, single-line JSON and omits absent fields" do
    json = MCPC::JsonRpc::Notification.new("notifications/initialized").to_json
    json.should eq(%({"jsonrpc":"2.0","method":"notifications/initialized"}))
  end
end
