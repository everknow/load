defmodule Stats do

  use GenServer

  require Logger

  @stats %{
    last_ms: 0, # last time stats were collected
    requests: 0,
    succeeded: 0,
    failed: 0,
    latencies: []
  }

  @impl true
  def init(args) do

    :pg.join(args.group, self())
    state = args
    |> Map.put(:start_date_time, DateTime.utc_now())
    |> Map.put(:stats_interval_ms, apply(:timer,
      Application.get_env(:load, :stats_timeunit, :seconds), [
      Application.get_env(:load, :stats_interval, 1)
    ]))
    |> Map.merge(Stats.empty())

    {:ok, state}
  end

  @impl true
  def handle_info({:update, stats}, state) do
    Logger.debug("Updating stats in #{state.group}")
    Logger.debug("Stats last_ms: #{stats.last_ms} | State last_ms: #{state.last_ms}")

    state =
      Map.merge(state, stats, fn
        :last_ms, current_value, new_value -> if new_value > current_value, do: new_value, else: current_value  
        _key, old_value, increment when is_number(old_value) -> old_value + increment
        _key, old_value, increment when is_list(old_value) -> increment ++ old_value
      end)

    state = case state.group do
      Local -> maybe_update(state, WS)
      Global -> maybe_update(state, nil)
    end

    {:noreply, state}
  end

  @impl true
  def handle_call(:get , _from, state) do
    {:reply, state |> Map.take([:history | Map.keys(Stats.empty())]), state}
  end

  defp get_object_based_on_dest(dest) do 
    case dest do 
      Local -> :worker
      WS -> :local
      nil -> :global
    end
  end

  @doc """
  Update worker state and Local and Global stats
  """
  def maybe_update(state, dest \\ Local) do
    object = get_object_based_on_dest(dest)

    Logger.debug("#{object} - maybe_update - dest: #{dest}")
    now = DateTime.utc_now |> DateTime.to_unix(:millisecond)
    duration = now - state.last_ms
    Logger.debug("#{object} - Duration: #{duration} ms")

    if duration > state.stats_interval_ms do
      state =
        if Map.has_key?(state, :history) do
          Logger.debug("#{object} - Update history entry")
       
          max = get_max_latency(state)
          min = get_min_latency(state)
          avg = get_avg_latency(state)

          # Get number of requests for the duration
          latest_requests = Enum.count(state.latencies)
          duration_second = duration / 1000
          duration_since_start_second = DateTime.diff(DateTime.utc_now, state.start_date_time)

          Logger.debug("#{object} - Latest_requests: #{inspect(state.latencies)}")

          %{state | history: %{
            last_requests_rate: safe_div(latest_requests, duration_second),
            requests_rate: safe_div(state.requests, duration_since_start_second),
            succeeded_rate: safe_div(state.succeeded, duration_since_start_second),
            failed_rate: safe_div(state.failed, duration_since_start_second),
            latency: %{avg: avg, max: max, min: min}}}
        else
          state
        end

      # Update Local and Global (via WS)
      :pg.get_local_members(dest)
      |> Enum.each(&send(&1, {:update, state |> Map.take(Map.keys(Stats.empty()))}))

      # Reset stats if worker or local stats.
      if !is_nil(dest) do  
        Map.merge(state, %{Stats.empty() | last_ms: now})
      else
        %{state | latencies: [], last_ms: now}
      end
    else
      Logger.info("#{object} - State wasn't updated")
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

  defp get_max_latency(%{latencies: []}), do: nil 
  defp get_max_latency(%{latencies: latencies, history: %{latency: %{max: history_max}}})do 
    current_max = Enum.max(latencies)

    if is_nil(history_max) or current_max > history_max do 
      current_max
    else
      history_max
    end
  end

  defp get_min_latency(%{latencies: []}), do: nil
  defp get_min_latency(%{latencies: latencies, history: %{latency: %{min: history_min}}}) do 
    current_min = Enum.min(latencies)

    if is_nil(history_min) or current_min < history_min do
      current_min
    else
      history_min
    end
  end

  defp get_avg_latency(%{latencies: [], requests: 0}), do: nil
  
  defp get_avg_latency(%{latencies: latencies, requests: total_requests, history: %{latency: %{avg: nil}}}) do 
    Enum.sum(latencies) * (Enum.count(latencies) / total_requests)
  end
  
  defp get_avg_latency(%{latencies: latencies, requests: total_requests, history: %{latency: %{avg: history_avg}}}) do 
    previous_requests = total_requests - Enum.count(latencies)
    
    (history_avg * (previous_requests / total_requests) + Enum.sum(latencies) / total_requests)
    |> trunc()
  end
end
