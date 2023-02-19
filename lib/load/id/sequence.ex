defmodule Load.Id.Sequence do

  use GenServer

  @impl true
  def init(args) do
    state = args
    |> Map.merge(%{
      next_id_batch_size: Application.get_env(Load, :next_id_batch_size, 10)
    })
    {:ok, state}
  end

  @impl true
  def handle_info({:set_next_id, id}, state) do
    {:noreply, state |> Map.put(:next_id, id)}
  end

  @impl true
  def handle_call(:next_id_batch , _from, state) do
    if state.next_id do
      next_id = state.next_id + state.next_id_batch_size
      {:reply, state.next_id..(next_id - 1) |> Enum.into([]), %{state | next_id: next_id}}
    else
      {:reply, [], state}
    end
  end

end
