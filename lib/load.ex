defmodule Load do

  require Logger

  def scale(count, address \\ :all) when is_integer(count) and count > 0 and (address == :all or is_binary(address)) do
    DynamicSupervisor.which_children(Load.Connection.Supervisor)
    |> Enum.each(fn {:undefined, pid, :worker, [Load.WSClient]} ->
      GenServer.cast(pid, {:ws_send, address, %{command: "scale", count: count}})
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

  # configure(%{
  #  sim: ChainLoad.ERC20.Sim,
  #  config_mod: ChainLoad.WorkerNodeConfigurator
  #})
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

  def q, do: Stats.get()

  def h, do:
    IO.puts(
      "+-----------------------------------------------\n"
    <>"| Commands available:\n"
    <>"| Load.scale  (count, :all | address) - scale to count workers on selected nodes\n"
    <>"| Load.connect(addresses)             - connect to addresses\n"
    <>"| Load:q() - print current stats\n"
    <>"+-----------------------------------------------"
    )

end
