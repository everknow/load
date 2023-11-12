defmodule Sim.Subscriber do

  @behaviour Load.Sim

  require Logger

  # group: RefSubscribers
  @impl true
  def init(state) do
    state
    |> Map.merge(%{
      pending: %{}
    })
  end

  @impl true
  def run(%{pending: pending} = state) do
    now = now()
    count = Enum.count(pending)
    pending = pending |> Map.reject(fn {_k, v} -> now > v + 60000 end)
    %{state | pending: pending, failures: state.failures + (count - Enum.count(pending))}
  end

  @impl true
  def handle_message({:reg, ref}, state) do
    Logger.debug("[#{__MODULE__}] reg #{inspect(ref)}")
    %{state | pending: state.pending |> Map.put(ref, now())}
  end

  @impl true
  def handle_message({:gun_ws, _conn, _, {:text, message}}, %{avg_latency: avg_latency} = state) do
    %{"completed" => ref} = Jason.decode!(message)
    case state.pending[ref] do
      nil ->
        state
      init_time ->
        latency = now()-init_time
        avg_latency = if avg_latency  do
          (avg_latency + latency)/2
        else
          latency
        end
        %{state | avg_latency: avg_latency}
    end
  end

  defp now, do: DateTime.utc_now |> DateTime.to_unix(:millisecond)

end
