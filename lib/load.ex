defmodule Load do
  require Logger

  def scale(count, address \\ :all)
      when is_integer(count) and count > 0 and (address == :all or is_binary(address)) do
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

  def stop() do
    DynamicSupervisor.which_children(Load.Worker.Supervisor)
    |> Enum.each(fn {_id, pid, :worker, _} ->
      send(pid, :exit)
    end)
  end

  def i, do: Stats.get()

  def h,
    do:
      IO.puts(
        "+-----------------------------------------------\n" <>
          "| Commands available:\n" <>
          "| Load.scale  (count, :all | address) - scale to count workers on selected nodes\n" <>
          "| Load.connect(addresses)             - connect to addresses\n" <>
          "| Load:i() - print current stats\n" <>
          "+-----------------------------------------------"
      )
end
