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
    stats = stats
    |> Map.new(fn {k, v} ->
      if state.stats[k] do
        {k, state.stats[k] |> Map.merge(v, fn k, v1, v2 ->
          if k == :avg_latency do
            if v1, do: (v1 + v2) / 2, else: v2
          else
            v1 + v2
          end
        end)}
      else
        {k, v}
      end
    end)

    state = %{state | stats: stats}

    state =
      case state.group do
        Local -> maybe_update(state, WS)
        Global -> maybe_update(state, Subscriber)
      end

    {:noreply, state}
  end

  defp maybe_update(%{"stats_interval_ms" => stats_interval_ms} = state, dest) do
    now = now()
    duration = now - state.last_ms
    if duration > stats_interval_ms do
      state = if state[:history] do
        %{state | history: [{now, state.stats} | state.history]}
      else
        state
      end
      :pg.get_local_members(dest)
      |> Enum.each(&send(&1, {:update, state.stats}))
      %{
        state | last_ms: now, stats: state.stats
        |> Map.to_list()
        |> Enum.map(fn {sim, stats} ->
          {sim, Map.merge(stats, Stats.empty())}
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
