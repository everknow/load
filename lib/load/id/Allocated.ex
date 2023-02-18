defmodule Load.Id.Allocated do

  use GenServer

  @impl true
  def init(args) do
    state = args
    |> Map.merge(%{
      allocated: []
    })
    {:ok, state}
  end

  @impl true
  def handle_info({:next_id_batch, next_id_batch}, state) do
    {:noreply, %{state | allocated: state.allocated ++ next_id_batch}}
  end

  @impl true
  def handle_call(:next_id , _from, state) do
    if state.allocated |> length() < 5 do
      :pg.get_local_members(WS)
      |> Enum.each(&send(&1, :ask_new_batch))
    end
    case state.allocated do
      [] -> {:reply, nil, state}
      [next | more] -> {:reply, next, %{state | allocated: more}}
    end
  end

  def test do
    send(IdSequence, {:set_next_id, 5})
    Load.connect
    GenServer.call(IdAllocated, :next_id)
  end

end
