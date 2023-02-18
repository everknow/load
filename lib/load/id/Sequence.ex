defmodule Load.Id.Sequence do

  use GenServer

  @impl true
  def init(args) do
    :erlang.register(__MODULE__, self())
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
      {:reply, state.next_token_id..state.next_token_id+(state.next_id_batch_size - 1), %{state | next_token_id: state.next_token_id + state.next_id_batch_size}}
    else
      {:reply, [], state}
    end
  end

end
