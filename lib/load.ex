defmodule Load do

  require Logger

  def scale(count, sim, address \\ :all) when is_integer(count) and count >= 0 do
    sim = if sim, do: sim, else: Application.fetch_env!(:load, :sim)
    DynamicSupervisor.which_children(Load.Connection.Supervisor)
    |> Enum.each(fn {:undefined, pid, :worker, [Load.WSClient]} ->
      GenServer.cast(pid, {:ws_send, address, %{command: "scale", sim: sim, count: count}})
      end)
  end

  def autoscale(config) do
    send(Scaler, {:configure, config})
  end

  def count(sim, address \\ :all) do
    sim = if sim, do: sim, else: Application.fetch_env!(:load, :sim)
    DynamicSupervisor.which_children(Load.Connection.Supervisor)
    |> Enum.map(fn {:undefined, pid, :worker, [Load.WSClient]} ->
      GenServer.cast(pid, {:ws_send, address, %{command: "count", sim: sim}})
      end)
    end

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
    children = DynamicSupervisor.which_children(Load.Connection.Supervisor)
    count = length(children)
    children = children |> Enum.zip(1..count)
    children |> Enum.each(fn {{:undefined, pid, :worker, [Load.WSClient]}, n} ->
      GenServer.cast(pid, {:ws_send, address, %{command: "configure",
      config: case Application.get_env(:load, :config_mod) do
        nil ->
          config
        config_mod ->
          config_mod.select(config, n, count)
      end}})
      end)
  end

  def subscribe(pid), do: :pg.join(Subscriber, pid)

  def h, do:
    IO.puts("""
    Commands available: - parameters with ? suffix are optional\n
    Load.scale(count, sim?) - scale to count workers for sim\n
    Load.count(sim?) - lists number of active workers for sim by node\n
    Load.connect(addresses?) - connect master to slave addresses\n
    Load.configure                      - TODO\n
    Load.subscribe                      - TODO
    """)

end
