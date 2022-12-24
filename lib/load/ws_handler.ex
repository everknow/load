defmodule Load.WSHandler do

  @behaviour :cowboy_websocket

  require Logger

  @impl true
  def init(req, _state) do
    state = %{caller: req.pid}
    :pg.join(WS, state.caller)
    Process.send_after(state.caller, :ping, 5000)
    {:cowboy_websocket, req, state}
  end

  @impl true
  def websocket_handle(:pong, state) do
    Process.send_after(state.caller, :ping, 5000)
    Logger.debug("pong")
    {:ok, state}
  end

  @impl true
  def websocket_handle(:ping, state) do
    Logger.debug("received ping from gun")
    {:ok, state}
  end

  @impl true
  def websocket_handle({:text, message}, state) do
    case Jason.decode!(message) do
      %{"command" => "terminate"} ->
        Supervisor.which_children(Load.Worker.Supervisor)
        |> Enum.each(fn {:undefined, pid, :worker, [Load.Worker]} ->
          DynamicSupervisor.terminate_child(Load.Worker.Supervisor, pid)
        end)
        {:stop, state}
      %{"command" => "scale", "sim" => sim, "count" => count} ->
        count = Supervisor.which_children(Load.Worker.Supervisor)
        |> Enum.reduce(count, fn {:undefined, pid, :worker, [Load.Worker]}, acc ->
          case pid |> :sys.get_state() do
            %{sim: "Elixir."<>^sim} ->
              acc = acc - 1
              if acc < 0 do
                DynamicSupervisor.terminate_child(Load.Worker.Supervisor, pid)
              end
            _ ->
              acc
          end
        end)
        sim = "Elixir."<>sim |> String.to_existing_atom()
        if count > 0 do
          1..count
          |> Enum.each(fn _ ->
            DynamicSupervisor.start_child(Load.Worker.Supervisor, {Load.Worker, sim: sim})
          end)
        end
        {:reply, {:text, Jason.encode!(%{ok: :ok})}, state}
      %{"command" => "count", "sim" => sim} ->
        count = Supervisor.which_children(Load.Worker.Supervisor)
        |> Enum.reduce(0, fn {:undefined, pid, :worker, [Load.Worker]}, acc ->
          case pid |> :sys.get_state() do
            %{sim: "Elixir."<>^sim} ->
              acc + 1
            _ ->
              acc
          end
        end)
        {:reply, {:text, Jason.encode!(%{count: count})}, state}
      %{"command" => "configure", "config" => config} ->
        if config["config_mod"], do: String.to_existing_atom(config["config_mod"]).configure(config)
        {:reply, {:text, Jason.encode!(%{ok: :ok})}, state}
      _ ->
        # IO.puts("received #{message}")
        {:reply, {:text, "invalid"}, state}
    end
  end

  @impl true
  def websocket_info({:notify, message}, state) do
    Logger.debug("forwarding message")
    {:reply, {:text, Jason.encode!(%{notify: message})}, state}
  end

  @impl true
  def websocket_info({:update, stats}, state) do
    Logger.debug("forwarding stats")
    {:reply, {:text, Jason.encode!(%{update: stats})}, state}
  end

  @impl true
  def websocket_info(:ping, state) do
    Logger.debug("ping")
    {:reply, :ping, state}
  end

  @impl true
  def websocket_info(message, state) do
    Logger.warn("received  message:  #{inspect(message)}")
    {:ok, state}
  end

  @impl true
  def terminate(_reason, _req, _state) do
    Logger.info("terminated")
    :pg.leave(WS, self())
    :ok
  end

end
