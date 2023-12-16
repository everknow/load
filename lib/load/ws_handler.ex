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

      %{"command" => "configure", "config" => config} ->
        Logger.debug("[#{__MODULE__}] #{inspect(config)}")

        if config["gen"], do:
          Supervisor.start_child(Load.Supervisor, %{id: Gen, start: {GenServer, :start_link, [Load.Container, %{
            os_command: config["gen"]["os_command"],
            os_dir: config["gen"]["os_dir"],
            os_env: config["gen"]["os_env"] |> Enum.map(fn {k,v}-> {String.to_charlist(k), String.to_charlist(v)} end),
            serializer: config["serializer"],
            common: config["common"]
            }, [name: Gen]]
          }})
        {:reply, {:text, Jason.encode!(%{ok: :ok})}, state}

      %{"command" => "generate", "quantity" => quantity} ->
        Logger.debug("[#{__MODULE__}] generate quantity: #{inspect(quantity)}")
        send(Gen, {:generate, quantity})
        {:reply, {:text, Jason.encode!(%{ok: :ok})}, state}

      
      %{"command" => "create_accounts", "force" => force} ->
        Logger.debug("[#{__MODULE__}] create_accounts force: #{inspect(force)}")
        send(Gen, {:create_accounts, force})
        {:reply, {:text, Jason.encode!(%{ok: :ok})}, state}

      %{"command" => "restart_gen", "config" => changes} ->
        if Process.whereis(Scaler) do
          Supervisor.terminate_child(Load.Supervisor, Scaler)
          Supervisor.delete_child(Load.Supervisor, Scaler)
          Supervisor.start_child(Load.Supervisor, %{id: Scaler, start: {GenServer, :start_link, [Load.Scaler, %{}, [name: Scaler]]}})
        end
        if Process.whereis(Gen) do
          config = :sys.get_state(Gen)
          Supervisor.terminate_child(Load.Supervisor, Gen)
          Supervisor.delete_child(Load.Supervisor, Gen)
          Supervisor.start_child(Load.Supervisor, %{id: Gen, start: {GenServer, :start_link, [Load.Container, %{
            os_command: config.os_command,
            os_dir: config.os_dir,
            os_env: config.os_env,
            serializer: config.serializer,
            common: config.common
            } |> Map.merge(changes |> Map.new(fn {k,v} -> {String.to_atom(k),v} end), fn _k,v1,v2 -> if v2, do: v2, else: v1 end), [name: Gen]]
          }})
          Supervisor.which_children(Load.Hitter.Supervisor)
          |> Enum.each(fn {_, pid, :worker, _} ->
            DynamicSupervisor.terminate_child(Load.Hitter.Supervisor, pid)
          end)
        end
        {:reply, {:text, Jason.encode!(%{ok: :ok})}, state}

      %{"command" => "terminate"} ->
        Supervisor.which_children(Load.Hitter.Supervisor)
        |> Enum.each(fn {:undefined, pid, :worker, [Load.Worker]} ->
          DynamicSupervisor.terminate_child(Load.Hitter.Supervisor, pid)
        end)
        {:stop, state}
      
      %{"command" => "scale", "config" => config} ->
        sims = config["sims"]
        sim = config["sim"]
        sim = if String.starts_with?(sim, "Elixir."), do: sim, else: "Elixir."<>sim
        sim = sim |> String.to_existing_atom()
        increment = Supervisor.which_children(Load.Hitter.Supervisor)
        |> Enum.reduce(sims, fn {:undefined, pid, :worker, [Load.Worker]}, acc ->
          case pid |> :sys.get_state() do
            %{sim: ^sim} ->
              acc = acc - 1
              if acc < 0 do
                DynamicSupervisor.terminate_child(Load.Hitter.Supervisor, pid)
              end
              acc
            _ ->
              acc
          end
        end)
        if increment > 0 do
          1..increment
          |> Enum.each(fn _ ->
            ret = DynamicSupervisor.start_child(Load.Hitter.Supervisor, {Load.Worker, [
              sim: sim,
              host: Enum.random(config["hit_hosts"]),
              port: config["rpc_port"],
              protocol: config["protocol"],
              statement: config["statement"],
              interval_ms: apply(:timer, config["worker_tick_timeunit"] |> String.to_atom(), [config["worker_tick_interval"]]),
              stats_interval_ms: apply(:timer, config["stats_tick_timeunit"] |> String.to_atom(), [config["stats_tick_interval"]])
              ] ++ (config |> Map.take([]) |> Map.to_list() |> Enum.map(fn {k,v} -> {String.to_atom(k), v} end))
            })
            Logger.debug("spawned child ret: #{inspect(ret)}")
          end)
        end
        {:reply, {:text, Jason.encode!(%{ok: :ok})}, state}
      
      %{"command" => "count", "sim" => sim} ->
        sim = if String.starts_with?(sim, "Elixir."), do: sim, else: "Elixir."<>sim
        sim = sim |> String.to_existing_atom()
        count = Supervisor.which_children(Load.Hitter.Supervisor)
        |> Enum.reduce(0, fn {:undefined, pid, :worker, [Load.Worker]}, acc ->
          case pid |> :sys.get_state() do
            %{sim: ^sim} ->
              acc + 1
            _ ->
              acc
          end
        end)
        {:reply, {:text, Jason.encode!(%{count: count})}, state}

      %{"next_id_batch" => next_id_batch} ->
        Logger.debug(next_id_batch, label: "received batch")
        send(IdAllocated, {:next_id_batch, next_id_batch})
        {:ok, state}

      %{"notify" => message, "routing" => [pid64]} ->
        Logger.debug("[#{__MODULE__}] notify: #{message}")
        if pid64 != "" do
          pid = Load.to_pid(pid64)
          send(pid, {:notify, message})
        end
        {:ok, state}
      _ ->
        # IO.puts("received #{message}")
        {:reply, {:text, "invalid"}, state}
    end
  end

  @impl true
  def websocket_info({:ws_send, message}, state) do
    Logger.info("[#{__MODULE__}] ws_send message: #{inspect(message)}")
    {:reply, {:text, Jason.encode!(message)}, state}
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
    Logger.debug("ws prep_accounts")
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
