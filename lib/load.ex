defmodule Load do

  require Logger

  def connect(addresses \\ ["localhost"]) when is_list(addresses) do
    DynamicSupervisor.which_children(Load.Connection.Supervisor)
    |> Enum.reduce(MapSet.new(addresses), fn {:undefined, pid, :worker, [Load.WSClient]}, acc ->
      address = GenServer.call(pid, :get_address)
      if MapSet.member?(acc, address) do
        MapSet.delete(acc, address)
      else
        GenServer.cast(pid, {:ws_send, address, %{command: "terminate"}})
        acc
      end
    end)
    |> Enum.each(fn address ->
      DynamicSupervisor.start_child(Load.Connection.Supervisor, {Load.WSClient, address: address})
    end)
  end

  def configure(config, address \\ :all) do
    Logger.debug("[#{__MODULE__}] #{inspect(config)}")
    DynamicSupervisor.which_children(Load.Connection.Supervisor)
    |> Enum.each(fn {:undefined, pid, :worker, [Load.WSClient]} ->
      GenServer.cast(pid, {:ws_send, address, %{"command" => "configure", "config" => config}})
      end)
  end

  def autoscale(config), do: send(Scaler, {:configure, config})

  def subscribe(pid), do: :pg.join(Subscriber, pid)

  def h, do:
    IO.puts("""
    Commands available: - parameters with ? suffix are optional\n
    Load.connect(addresses?) - connect master to slave addresses\n
    Load.configure(config) - alters the configuration\n
    Load.autoscale(config) - initiates a load with an autoscale configuration\n
    Load.subscribe(pid)
    """)

end
