defmodule Load.Scaler do
  use GenServer

  @impl true
  def init(args) do
    state = args
    {:ok, state}
  end

  @impl true
  def handle_info({:configure, config}, state) do
    state = state
    |> Map.merge(%{
      expiry: now() + apply(:timer, config["test_duration_timeunit"] |> String.to_existing_atom(), [config["test_duration_interval"]]),
      tick_ms: apply(:timer, config["scale_tick_timeunit"] |> String.to_existing_atom(), [config["scale_tick_interval"]]),
      tick_count: 0,
      function: case config["scale_function"] do
        "uniform" ->
          height = config["scale_height"]
          fn _x -> height end
        "ramp" ->
          {growth_coefficient, max_height} = {config["scale_growth_coefficient"] |> Float.parse() |> elem(0), config["scale_height"]}
          fn x -> min( round(x * growth_coefficient), max_height) end
        "square" ->
          {width, height} = {config["scale_width"], config["scale_height"]}
          fn x -> rem( round(x/width), 2) * height end
      end,
      config: config |> Map.take(["worker_tick_timeunit","worker_tick_interval","stats_tick_timeunit","stats_tick_interval","sim", "hit_hosts", "rpc_port", "protocol", "statement"])
      })

    Process.send_after(self(), :rescale, state.tick_ms)
    {:noreply, state}
  end

  @impl true
  def handle_info(:rescale, state) do
    Process.send_after(self(), :rescale, state.tick_ms)
    scale(state.function.(state.tick_count))
    {:noreply, %{state | tick_count: state.tick_count + 1}}
  end

  def scale(quantity, address \\ :all) do
    DynamicSupervisor.which_children(Load.Connection.Supervisor)
    |> Enum.each(fn {:undefined, pid, :worker, [Load.WSClient]} ->
      # GenServer.cast(pid, {:ws_send, address, %{command: "scale", config: config, count: count}})
      GenServer.cast(pid, {:ws_send, address, %{command: "generate", quantity: quantity}})
      end)
  end

  def now, do: DateTime.utc_now |> DateTime.to_unix(:millisecond)
end
