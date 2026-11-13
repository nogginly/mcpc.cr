require "../spec_helper"

private def input_answering(content) : MCPC::ClientInput
  MCPC::ClientInput.new.tap do |input|
    input.elicitation_handler = ->(request : MCPC::ElicitationRequest) { request.accept(content) }
  end
end

private COMPLETE = JSON.parse(%({"resultType":"complete","content":[]}))
private ORIGINAL = MCPC::Params{"name" => JSON::Any.new("book_table")}

describe MCPC::Era::MultiRoundTrip do
  it "returns a complete result after one round" do
    rounds = 0
    result = MCPC::Era::MultiRoundTrip.new(MCPC::ClientInput.new, 3).run(ORIGINAL) do
      rounds += 1
      COMPLETE
    end
    result.should eq(COMPLETE)
    rounds.should eq(1)
  end

  it "treats a result without a resultType as complete" do
    legacy_shaped = JSON.parse(%({"content":[]}))
    MCPC::Era::MultiRoundTrip.new(MCPC::ClientInput.new, 3).run(ORIGINAL) { legacy_shaped }.should eq(legacy_shaped)
  end

  it "retries with the answers under the server's keys and the state echoed unchanged" do
    input_required = JSON.parse(fixture("InputRequiredResult", "input-required-result-with-request-state-only"))
      .as_h.merge({"inputRequests" => JSON.parse(%({"guests":{"method":"elicitation/create","params":{
        "message":"How many?","requestedSchema":{"type":"object","properties":{}}}}}))})
    seen = [] of MCPC::Params

    MCPC::Era::MultiRoundTrip.new(input_answering({"guests" => 4}), 3).run(ORIGINAL) do |params|
      seen << params
      seen.size == 1 ? JSON::Any.new(input_required) : COMPLETE
    end

    seen.first.should eq(ORIGINAL)
    seen.last["name"].should eq("book_table")
    seen.last["inputResponses"].should eq(JSON.parse(%({"guests":{"action":"accept","content":{"guests":4}}})))
    seen.last["requestState"].should eq(input_required["requestState"])
  end

  it "retries at once, with nothing but the state, when no input is requested" do
    state_only = JSON.parse(fixture("InputRequiredResult", "input-required-result-with-request-state-only"))
    seen = [] of MCPC::Params

    MCPC::Era::MultiRoundTrip.new(MCPC::ClientInput.new, 3).run(ORIGINAL) do |params|
      seen << params
      seen.size == 1 ? state_only : COMPLETE
    end

    seen.last.keys.sort!.should eq(["name", "requestState"])
  end

  it "does not carry state from one round into a round that has none" do
    with_state = JSON.parse(%({"resultType":"input_required","requestState":"first"}))
    without_state = JSON.parse(%({"resultType":"input_required","inputRequests":{}}))
    seen = [] of MCPC::Params

    MCPC::Era::MultiRoundTrip.new(MCPC::ClientInput.new, 5).run(ORIGINAL) do |params|
      seen << params
      {with_state, without_state, COMPLETE}[seen.size - 1]
    end

    seen[1]["requestState"].should eq("first")
    seen[2].has_key?("requestState").should be_false
  end

  it "gives up after the allowed number of rounds" do
    state_only = JSON.parse(%({"resultType":"input_required","requestState":"again"}))
    rounds = 0

    expect_raises(MCPC::InputRequiredError, "after 3 rounds") do
      MCPC::Era::MultiRoundTrip.new(MCPC::ClientInput.new, 3).run(ORIGINAL) do
        rounds += 1
        state_only
      end
    end
    rounds.should eq(3)
  end

  it "raises when the server asks for input nothing can supply" do
    sampling = JSON.parse(fixture("InputRequiredResult",
      "input-required-result-with-elicitation-and-sampling-and-request-state"))

    expect_raises(MCPC::InputRequiredError, "sampling/createMessage") do
      MCPC::Era::MultiRoundTrip.new(input_answering({"name" => "octocat"}), 3).run(ORIGINAL) { sampling }
    end
  end
end
