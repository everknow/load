defmodule Load.ConfigHandler do

  require Logger

  def init(req = %{method: "POST"}, state) do
    {:ok, data, req} = :cowboy_req.read_body(req)
    config = Jason.decode!(data)
    
    Logger.warn("#{inspect(config)}")
    
    Load.connect(config["connect_hosts"])


    # start a poller for this test (or 2 in case of bridge)

    DynamicSupervisor.start_child(Load.Poller.Supervisor, {Load.Worker, [
      {:sim, Sim.Poller} | (config["poller"]
      |> Enum.map(fn {k, v} -> {
        k |> String.to_atom(),
        if ["pos_decode", "pos_encode", "content_decode"] |> Enum.member?(k) do
          v |> String.to_existing_atom()
        end
      } end))
    ] ++ [
      host: config["common"]["hit_host"] |> to_charlist(),
      port: config["common"]["hit_port"]
    ]})

    if config["prep"], do:
    Supervisor.start_child(Load.Supervisor, %{id: Prep, start: {GenServer, :start_link, [Load.Container, 
      %{os_command: config["prep"]["exe"], start_command: config["prep"]["cfg"], serializer_cfg: config["serializer"]}, [name: Prep]]
    }})
          
    :timer.sleep(3000)

    Load.configure(config |> Map.take(["gen", "serializer"]))

    req = :cowboy_req.reply(200, 
      %{"content-type" => "text/plain"},
      Jason.encode!(%{success: true}),
      req)
    {:ok, req, state}
  end
end