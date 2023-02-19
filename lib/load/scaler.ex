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
      expiry: now() + apply(:timer, config["duration_timeunit"] |> String.to_existing_atom(), [config["duration_interval"]]),
      tick_ms: apply(:timer, config["tick_timeunit"] |> String.to_existing_atom(), [config["tick_interval"]]),
      tick_count: 0,
      function: case config["function"] do
        "uniform" ->
          height = config["scale_height"]
          fn _x -> height end
        "ramp" ->
          {growth_coefficient, max_height} = {config["scale_growth_coefficient"], config["scale_max_height"]}
          fn x -> min(x * growth_coefficient, max_height) end
        "square" ->
          {width, height} = {config["scale_width"], config["scale_height"]}
          fn x -> rem( round(x/width), 2) * height end
      end,
      sim: config["sim"]
      })

    Process.send_after(self(), :rescale, state.tick_ms)
    {:noreply, state}
  end

  @impl true
  def handle_info(:rescale, state) do
    cond do
      now() < state.expiry ->
        Load.scale(state.function(state.tick_count), state.sim)
        Process.send_after(self(), :rescale, state.tick_ms)
        {:noreply, state}
      true ->
        {:noreply, state}
    end
  end

  def now, do: DateTime.utc_now |> DateTime.to_unix(:millisecond)
end
