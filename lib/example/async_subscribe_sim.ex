defmodule Example.AsyncSubscribeSim do

  @behaviour Load.Sim

  require Logger

  @impl true
  def init do
    Application.get_env(:load, __MODULE__, %{})
    |> Map.merge(%{
      pending: %{},
      group: RefSubscribers
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
  def handle_message({:register, ref}, state) do
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
