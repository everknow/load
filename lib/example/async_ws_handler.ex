defmodule Load.AsyncWSHandler do

  @behaviour :cowboy_websocket

  require Logger

  @impl true
  def init(req, _state) do
    state = %{caller: req.pid}
    :pg.join(AsyncWS, state.caller)
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
      _ ->
        # IO.puts("received #{message}")
        {:reply, {:text, "invalid"}, state}
    end
  end

  @impl true
  def websocket_info(:ping, state) do
    Logger.debug("ping")
    {:reply, :ping, state}
  end

  @impl true
  def websocket_info({:complete, ref}, state) do
    Logger.debug("forwarding ref")
    {:reply, {:text, Jason.encode!(%{complete: ref})}, state}
  end

  @impl true
  def websocket_info(message, state) do
    Logger.warn("received  message:  #{inspect(message)}")
    {:ok, state}
  end

  @impl true
  def terminate(_reason, _req, _state) do
    Logger.info("terminated")
    :pg.leave(AsyncWS, self())
    :ok
  end

end
