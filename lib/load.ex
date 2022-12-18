defmodule Load do

  require Logger

  def scale(count, sim, address \\ :all) when is_integer(count) and count >= 0 and (address == :all or is_binary(address)) do
    DynamicSupervisor.which_children(Load.Connection.Supervisor)
    |> Enum.each(fn {:undefined, pid, :worker, [Load.WSClient]} ->
      GenServer.cast(pid, {:ws_send, address, %{command: "scale", sim: sim, count: count}})
      end)
  end

  def count(sim) do
    DynamicSupervisor.which_children(Load.Connection.Supervisor)
    |> Enum.map(fn {:undefined, pid, :worker, [Load.WSClient]} ->
      GenServer.cast(pid, {:ws_send, :all, %{command: "count", sim: sim}})
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
      config: if config.config_mod do
        config.config_mod.select(config, n, count)
      else
        config
      end}})
      end)
  end

  def subscribe(pid), do: :pg.join(Subscriber, pid)

  def h, do:
    IO.puts("""
    Commands available:\n
    Load.scale(count, sim, :all | address) - scale to count workers for sim on selected nodes\n
    Load.count(sim) - lists number of active workers for sim by node\n
    Load.connect(addresses) - connect master to slave addresses\n
    Load.configure                      - TODO
    Load.subscribe                      - TODO
    """)

end
