defmodule Load.WSHandler do

  @behaviour :cowboy_websocket

  require Logger

  @impl true
  def init(req, _state) do
    state = %{caller: req.pid, protocols: [:http], transport: :tcp}
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
      %{"command" => "scale", "count" => count} ->
        count = Supervisor.which_children(Load.Worker.Supervisor)
        |> Enum.reduce(count, fn {:undefined, pid, :worker, [Load.Worker]}, acc ->
          acc = acc - 1
          if acc < 0 do
            DynamicSupervisor.terminate_child(Load.Worker.Supervisor, pid)
          end
          acc
        end)
        1..count
        |> Enum.each(fn _ ->
          DynamicSupervisor.start_child(Load.Worker.Supervisor, {Load.Worker, [sim: Application.get_env(:load, :sim, Example.EchoSim)]})
        end)
        {:reply, {:text, Jason.encode!(%{ok: :ok})}, state}
      %{"command" => "configure", "config" => config} ->
        # mandatory to have a sim
        Application.put_env(:load, :sim, config["sim"] |> String.to_existing_atom())
        if config_mod = config["config_mod"] |> String.to_existing_atom(), do: config_mod.configure(config)
        {:reply, {:text, Jason.encode!(%{ok: :ok})}, state}
      _ ->
        # IO.puts("received #{message}")
        {:reply, {:text, "invalid"}, state}

    end

  end

  @impl true
  def websocket_info({:notify, message}, state) do
    Logger.info("forwarding message")
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
