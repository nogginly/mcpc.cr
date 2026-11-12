# Records the events a client reports.
class EventLog
  getter events = [] of Mcpc::Event

  def initialize(client : Mcpc::Client)
    client.on_event { |event| events << event }
  end

  def of(type : T.class) : Array(T) forall T
    events.compact_map(&.as?(T))
  end

  def await(type : T.class) : T forall T
    wait_until { !of(type).empty? }
    of(type).first
  end
end
