defmodule Stats do

  use GenServer

  require Logger

  @stats %{
    requests: 0,
    succeeded: 0,
    failed: 0,
    avg_latency: nil
  }

  @impl true
  def init(args) do

    Logger.debug("[#{__MODULE__}] init #{inspect(args)}")

    :pg.join(args.group, self())
    state = args
    |> Map.merge(%{
      "stats_interval_ms" => apply(:timer,
      Application.get_env(:load, :stats_timeunit, :seconds), [
      Application.get_env(:load, :stats_interval, 1)
      ]),
      last_ms: now(),
      stats: %{}
    })

    {:ok, state}
  end

  @impl true
  def handle_info({:update, stats}, state) do
    if state.group == Global, do: Logger.debug("[#{__MODULE__}] handle_info #{inspect({:update, stats})}")
    stats = stats
    |> Map.new(fn {k, v} ->
      if state.stats[k] do
        {k, state.stats[k] |> Map.merge(v, fn k, v1, v2 ->
          if k == :avg_latency do
            cond do
              is_nil(v2) -> v1
              is_nil(v1) -> v2
              true -> (v1 + v2) / 2
            end
          else
            v1 + v2
          end
        end)}
      else
        {k, v}
      end
    end)

    state = %{state | stats: state.stats |> Map.merge(stats)}

    state =
      case state.group do
        Local -> maybe_update(state, WS)
        Global -> maybe_update(state, Subscriber)
      end

    {:noreply, state}
  end

  defp maybe_update(%{"stats_interval_ms" => stats_interval_ms} = state, dest) do
    if state.group == Global, do: Logger.debug("[#{__MODULE__}] maybe_update #{inspect(state)}")
    now = now()
    duration = now - state.last_ms
    if duration > stats_interval_ms do
      state = if state[:history] do
        %{state | history: [{{now, make_ref()}, state.stats} | state.history] |> Enum.take(state[:history_retention] || 20)}
      else
        state
      end
      :pg.get_local_members(dest)
      |> Enum.each(&send(&1, {:update, state.stats}))
      %{
        state | last_ms: now, stats: state.stats
        |> Map.to_list()
        |> Enum.map(fn {sim, stats} ->
          {sim, (if state.group == Global, do: stats, else: Map.merge(stats, Stats.empty()))}
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

  def now, do: DateTime.utc_now |> DateTime.to_unix(:millisecond)

end
