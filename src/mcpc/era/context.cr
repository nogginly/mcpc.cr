module MCPC
  # How the client behaves differs by protocol era; each era is a `Strategy`.
  module Era
    # The collaborators every era strategy works with.
    record Context,
      router : JSONRPC::Router,
      transport : Transport,
      config : Config,
      events : EventDispatcher,
      input : ClientInput
  end
end
