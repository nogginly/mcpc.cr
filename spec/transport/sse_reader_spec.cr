require "../spec_helper"

private def messages_in(stream : String) : Array(String)
  messages = [] of String
  Mcpc::Transport::SseReader.new(IO::Memory.new(stream)).each_message { |data| messages << data }
  messages
end

describe Mcpc::Transport::SseReader do
  it "yields the data of each event" do
    messages_in("event: message\ndata: one\n\nevent: message\ndata: two\n\n").should eq(["one", "two"])
  end

  it "treats an event without a type as a message" do
    messages_in("data: plain\n\n").should eq(["plain"])
  end

  it "joins the data lines of one event with newlines" do
    messages_in("data: {\ndata: }\n\n").should eq(["{\n}"])
  end

  it "skips comments used as keep-alives" do
    messages_in(": keep-alive\n\ndata: real\n\n:\n\n").should eq(["real"])
  end

  it "skips events of other types" do
    messages_in("event: endpoint\ndata: /messages\n\ndata: real\n\n").should eq(["real"])
  end

  it "accepts CRLF line endings and data without a space" do
    messages_in("data:tight\r\n\r\n").should eq(["tight"])
  end

  it "drops an event the stream ended in the middle of" do
    messages_in("data: whole\n\ndata: cut").should eq(["whole"])
  end
end
