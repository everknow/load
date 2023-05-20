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
        sim = if String.starts_with?(sim, "Elixir."), do: sim, else: "Elixir."<>sim
        sim = sim |> String.to_existing_atom()
        count = Supervisor.which_children(Load.Worker.Supervisor)
        |> Enum.reduce(count, fn {:undefined, pid, :worker, [Load.Worker]}, acc ->
          case pid |> :sys.get_state() do
            %{sim: ^sim} ->
              acc = acc - 1
              if acc < 0 do
                DynamicSupervisor.terminate_child(Load.Worker.Supervisor, pid)
              end
              acc
            _ ->
              acc
          end
        end)
        if count > 0 do
          1..count
          |> Enum.each(fn _ ->
            DynamicSupervisor.start_child(Load.Worker.Supervisor, {Load.Worker, sim: sim})
          end)
        end
        send(Producer, {count: count})
        {:reply, {:text, Jason.encode!(%{ok: :ok})}, state}
      %{"command" => "count", "sim" => sim} ->
        sim = if String.starts_with?(sim, "Elixir."), do: sim, else: "Elixir."<>sim
        sim = sim |> String.to_existing_atom()
        count = Supervisor.which_children(Load.Worker.Supervisor)
        |> Enum.reduce(0, fn {:undefined, pid, :worker, [Load.Worker]}, acc ->
          case pid |> :sys.get_state() do
            %{sim: ^sim} ->
              acc + 1
            _ ->
              acc
          end
        end)
        {:reply, {:text, Jason.encode!(%{count: count})}, state}
      %{"command" => "configure", "config" => config} ->
        # TODO start gen from config
        Supervisor.start_child(Load.Supervisor, %{id: Producer, start: {GenServer, :start_link, [Load.Container, %{os_dir: "/home/dperini/dev/zerg/gen/target/debug", os_command: "./gen", start_command: "#{config.count}#cosmos#10000#src#domcosmosdom\n", count: config.count}, [name: Producer]]}})

        {:reply, {:text, Jason.encode!(%{ok: :ok})}, state}
      %{"next_id_batch" => next_id_batch} ->
        Logger.debug(next_id_batch, label: "received batch")
        send(IdAllocated, {:next_id_batch, next_id_batch})
        {:ok, state}
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
  def websocket_info(:ask_new_batch, state) do
    Logger.debug("asking new batch")
    {:reply, {:text, Jason.encode!(%{ask_new_batch: nil})}, state}
  end

  @impl true
  def websocket_info({:prep_accounts, message}, state) do
    Logger.debug("prep_accounts")
    {:reply, {:text, Jason.encode!(%{prep_accounts: message})}, state}
  end

  @impl true
  def websocket_info(:ping, state) do
    Logger.debug("ping")
    {:reply, :ping, state}
  end

  @impl true
  def websocket_info(message, state) do
    Logger.debug("received message:  #{inspect(message)}")
    {:ok, state}
  end

  @impl true
  def terminate(_reason, _req, _state) do
    Logger.info("terminated")
    :pg.leave(WS, self())
    :ok
  end

end
