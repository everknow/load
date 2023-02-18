defmodule Load.Id.Allocated do

  use GenServer

  @impl true
  def init(args) do
    :erlang.register(__MODULE__, self())
    state = args
    |> Map.merge(%{
      allocated: []
    })
    {:ok, state}
  end

  @impl true
  def handle_info({:next_id_batch, next_id_batch}, state) do
    {:noreply, %{state | allocated: [state.allocated ++ next_id_batch]}}
  end

  @impl true
  def handle_call(:next_id , _from, state) do
    if state.allocated |> length() < 5 do
      :pg.get_local_members(WS)
      |> Enum.each(&send(&1, "batch_gen_id"))
    end
    case state.allocated do
      [] -> {:reply, nil, state}
      [next | more] -> {:reply, next, %{state | allocated: more}}
    end
  end

end
