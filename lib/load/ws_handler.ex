defmodule Load.WSHandler do

  @behaviour :cowboy_websocket

  require Logger

  @impl true
  def init(req, _state) do
    state = %{caller: req.pid, transport: :http, protocols: [:ilp_packet]}
    :pg.join(WS, self())
    Process.send_after(state.caller, :ping, 5000)
    {:cowboy_websocket, req, state}
  end

  @impl true
  def websocket_handle(:ping, state) do
    Process.send_after(state.caller, :ping, 5000)
    Logger.debug("pong")
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
      _ ->
        {:reply, {:text, "invalid"}, state}
        # IO.puts("received #{message}")
    end

  end

  @impl true
  def websocket_info({:update, stats}, state) do
    Logger.info("forwarding stats")
    {:reply, {:text, Jason.encode!(%{stats: stats})}, state}
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
