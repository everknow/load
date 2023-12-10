defmodule Load.ConfigHandler do

  require Logger

  def init(req = %{method: "POST"}, state) do
    {:ok, data, req} = :cowboy_req.read_body(req)
    config = Jason.decode!(data)
    
    Logger.debug("[#{__MODULE__}] init #{inspect(config)}")
    
    Load.connect(config["connect_hosts"])

    DynamicSupervisor.start_child(Load.Poller.Supervisor, {Load.Worker,
      
      config["poller"]
      |> Enum.map(fn {k, v} -> {
        k |> String.to_atom(),
        if ["pos_decode", "pos_encode", "content_decode"] |> Enum.member?(k) do
          v |> String.to_atom()#to_existing_atom()
        else
          v
        end
      } end) |> Enum.into(%{
        sim: Sim.Poller,
        host: config["common"]["hit_host"] |> to_charlist(),
        port: config["common"]["hit_port"]
      })
    })
          
    :timer.sleep(3000)

    Load.configure(config |> Map.take(["gen", "serializer", "common"]))

    req = :cowboy_req.reply(200, 
      %{"content-type" => "text/plain"},
      Jason.encode!(%{success: true}),
      req)
    {:ok, req, state}
  end
end