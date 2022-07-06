defmodule Stats do
  use GenServer

  require Logger

  @stats %{
    # last time stats were collected
    last_ms: 0,
    requests: 0,
    succeeded: 0,
    failed: 0
  }

  @impl true
  def init(args) do
    :pg.join(args.group, self())

    state =
      args
      |> Map.put(
        :stats_interval_ms,
        apply(:timer, Application.get_env(:load, :stats_timeunit, :seconds), [
          Application.get_env(:load, :stats_interval, 1)
        ])
      )
      |> Map.merge(Stats.empty())

    {:ok, state}
  end

  @impl true
  def handle_info({:update, stats}, state) do
    state =
      Map.merge(state, stats, fn
        k, v1, v2 when k != :last_ms -> v1 + v2
        _, _, v2 -> v1
      end)

    case state.group do
      Local ->
        maybe_update(state, Global)

      Global ->
        maybe_update(state, nil)
    end

    {:noreply, state}
  end

  @impl true
  def handle_call(:get, _from, state) do
    {:reply, state |> Map.take([:history | Map.keys(Stats.empty())]), state}
  end

  def maybe_update(state, dest \\ Local) do
    now = DateTime.utc_now() |> DateTime.to_unix(:millisecond)
    duration = now - state.last_ms
    Logger.info("Duration: #{duration} ms")

    if duration > state.stats_interval_ms do
      state =
        if Map.has_key?(state, :history) do
          %{
            state
            | history: [
                %{
                  requests_rate: safe_div(state.requests, duration),
                  succeeded_rate: safe_div(state.succeeded, duration),
                  failed_rate: safe_div(state.failed, duration)
                }
                | state.history
              ]
          }
        else
          state
        end

      case dest do
        Local -> Logger.info("Update local stats process")
        Global -> Logger.info("Update global stats process")
        _ -> Logger.info("Nothing to update")
      end

      # Update only a specific set of fields
      stats_state = Map.take(state, Map.keys(Stats.empty()))

      :pg.get_local_members(dest)
      |> Enum.each(&send(&1, {:update, stats_state}))

      # Clean stats
      Map.merge(state, %{Stats.empty() | last_ms: now})
    else
      Logger.warn("State wasn't updated")
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

  def get do
    :pg.get_local_members(Global)
    |> Enum.map(&GenServer.call(&1, :get))
  end

  defp safe_div(count, duration_ms) do
    if duration_ms > 0 do
      count / duration_ms
    else
      0.0
    end
  end
end
