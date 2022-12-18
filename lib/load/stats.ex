defmodule Stats do

  use GenServer

  require Logger

  @stats %{
    requests: 0,
    succeeded: 0,
    failed: 0,
    avg_latency: 0.0
  }

  @impl true
  def init(args) do

    :pg.join(args.group, self())
    state = args
    |> Map.merge(%{
      stats_interval_ms: apply(:timer,
      Application.get_env(:load, :stats_timeunit, :seconds), [
      Application.get_env(:load, :stats_interval, 1)
      ]),
      last_ms: now(),
      stats: %{}
    })

    {:ok, state}
  end

  @impl true
  def handle_info({:update, sim, stats}, state) do
    stats = case state.stats[sim] do
      nil ->
        if state[:retain_history] do
          Map.put(stats, :history, [])
        else
          stats
        end
      _ ->
        Map.merge(state.stats[sim], stats, fn k, v1, v2 ->
          case k do
            :history -> v1
            :avg_latency -> (v1 + v2) / 2
            _ -> v1 + v2
          end
        end)
    end

    state = %{state | stats: Map.put(state.stats, sim, stats)}

    state =
      case state.group do
        Local -> maybe_update(state, WS)
        Global -> maybe_update(state, Subscriber)
      end

    {:noreply, state}
  end

  def maybe_update(state, dest \\ Local) do
    now = now()
    duration = now - state.last_ms
    if duration > state.stats_interval_ms do
      %{
        state | stats: state.stats
        |> Map.to_list()
        |> Enum.map(fn {sim, stats} ->
          :pg.get_local_members(dest)
          |> Enum.each(&send(&1, {:update, sim, stats |> Map.drop([:history])}))
          stats = if stats[:history] do
            %{stats | history: [stats |> Map.drop([:history]) | stats.history]}
          else
            stats
          end
          {sim, Map.merge(stats, Stats.empty() |> Map.drop([:avg_latency]))}
        end)
        |> Enum.into(%{})
      }
    else
      state
    end
  end

  @impl true
  def terminate(_reason, state) do
    Logger.info("terminated")
    :pg.leave(state.group, self())
    :ok
  end

  def empty, do: @stats

  defp now, do: DateTime.utc_now |> DateTime.to_unix(:millisecond)

end
