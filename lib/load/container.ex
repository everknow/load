defmodule Load.Container do

  use GenServer

  require Logger

  @queue 1
  @queue_reg 2
  @action 3
  @prep 4
  @generate 5

  @impl true
  def init(args) do

    Logger.debug("[#{__MODULE__}] #{inspect(args)}")
  
    state = args
    |> Map.merge(%{
      port: :ok,
      previous_chunk: "",
      serializers: %{}
    })
    port = :erlang.open_port({:spawn, state.os_command}, [:binary, :exit_status, cd: state.os_dir, env: state.os_env])

    # sent = :erlang.port_command(port, state.start_command)
    # if not sent, do: Logger.error("could not send to port")

    {:ok, %{state | port: port}}

  end

  @impl true
  def handle_info({:prep, message}, state) do
    Logger.debug("[#{__MODULE__}][#{state.os_command}] info #{inspect({:prep, message})}")
    sent = :erlang.port_command(state.port, <<@prep, byte_size(message)::integer-size(16), message>>)
    if not sent, do: Logger.error("[#{__MODULE__}][#{state.os_command}] port_command #{inspect({:prep, message})}")
    {:noreply, state}
  end

  @impl true
  def handle_info({:action, message}, state) do
    Logger.debug("[#{__MODULE__}][#{state.os_command}] info #{inspect({:action, message})}")
    sent = :erlang.port_command(state.port, <<@action, byte_size(message)::integer-size(16), message>>)
    if not sent, do: Logger.error("[#{__MODULE__}][#{state.os_command}] port_command #{inspect({:action, message})}")
    {:noreply, state}
  end

  @impl true
  def handle_info({:generate, quantity}, state) do
    Logger.debug("[#{__MODULE__}][#{state.os_command}] info #{inspect({:generate, quantity})}")
    sent = :erlang.port_command(state.port, <<@generate, quantity, 10>>)
    if not sent, do: Logger.error("[#{__MODULE__}][#{state.os_command}] port_command #{inspect({:generate, quantity})}")
    {:noreply, state}
  end

  @impl true
  def handle_info({port, {:data, chunk}}, state = %{port: port}) do
    handle_data(state.previous_chunk <> chunk, state)
  end

  def handle_data(data, state) do
    Logger.debug("[#{__MODULE__}][#{state.os_command}] data #{inspect(data)}")
    case data do
      <<@prep, message_size::16, message::binary-size(message_size), more_data::binary>> ->
        Logger.info("[#{__MODULE__}][#{state.os_command}] prep WS #{inspect(message)}")
        :pg.get_local_members(WS)
        |> Enum.each(&send(&1, {:prep, message}))
        handle_data(more_data, state)
      <<@queue, sid::8, message_size::16, message::binary-size(message_size), more_data::binary>> ->
        Logger.debug("[#{__MODULE__}][#{state.os_command}] queue #{inspect(message)}")
        {serializer, state_serializers} = if state.serializers[sid] do
          {state.serializers[sid], state.serializers}
        else
          {:ok, pid} = DynamicSupervisor.start_child(Load.Hitter.Supervisor, {Load.Serializer, %{
            "serializer" => state.serializer, "common" => state.common}})
          {pid, Map.put(state.serializers, sid, pid)}
        end
        send(serializer, {:hit, message})
        handle_data(more_data, %{state | serializers: state_serializers} )
      <<@queue_reg, _sid::8, _uuid::binary-size(36), message_size::16, message::binary-size(message_size), more_data::binary>> ->
        Logger.debug("[#{__MODULE__}][#{state.os_command}] queue_reg #{inspect(message)}")
        # send(state.serializers[sid], {:hit, {uuid, message}})
        handle_data(more_data, state)
      _ ->
        {:noreply, %{state | previous_chunk: data}}
    end
  end

end
