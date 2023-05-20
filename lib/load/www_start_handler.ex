defmodule Load.StartHandler do
  def init(req = %{method: "POST"}, state) do
    {:ok, data, req} = :cowboy_req.read_body(req)
    config = Jason.decode!(data)
    
    Load.connect(["localhost"])

    :timer.sleep(3000)

    #TODO start preparer(faucet, smart contract deployment etcetc..) as specified in config
    
    Supervisor.start_child(Load.Supervisor, %{id: PrepAccounts, start: {GenServer, :start_link, [Load.Container, %{os_dir: "/home/dperini/dev/zerg/faucet/target/debug", os_command: "./faucet", start_command: "cosmos#10000#src#domcosmosdom#0#1#power forum anger wash problem innocent rifle emerge culture offer among palace essay maid junior spin wife meat six gasp two rough boat marble\n", count: 0}, [name: PrepAccounts]]}})

    Load.configure(config) # for the other nodes (slaves)

    Load.autoscale(config)

    req = :cowboy_req.reply(200, 
      %{"content-type" => "text/plain"},
      Jason.encode!(%{success: true}),
      req)
    {:ok, req, state}
  end
end