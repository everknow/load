defmodule Example.AsyncSubscribeSim do

  @behaviour Load.Sim

  require Logger

  @impl true
  def init do
    :pg.join(RefSubscribers, self())
    Application.get_env(:load, __MODULE__, %{})
    |> Map.put(:pending, :gb_trees.empty())
  end

  @impl true
  def run(state) do #TODO run must behave as websocket this time
    payload = "example content"
    {:ok, res_payload, state} = Load.Worker.hit("POST /example/echo", [], payload, state)
    Logger.debug("sim received back #{res_payload}")
    state
  end

  @impl true
  def handle_message(message, %{pending: pending} = state) do
    case message do
      {:register_ref, ref} ->
        %{state | pending: :gb_trees.insert(ref, now(), pending)}
      _ ->
        state
    end
  end

  defp now, do: DateTime.utc_now |> DateTime.to_unix(:millisecond)

end
