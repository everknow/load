defmodule Load.Container do

  use GenServer

  require Logger

  @queue 1
  @master 2
  @gen 5
  @api 6
  @create_accounts 7

  @impl true
  def init(args) do

    Logger.debug("[#{__MODULE__}] #{inspect(args)}")
  
    state = args
    |> Map.merge(%{
      port: :ok,
      previous_chunk: "",
      serializers: %{},
      pending: MapSet.new()
    })
    port = :erlang.open_port({:spawn, state.os_command}, [:binary, :exit_status, cd: state.os_dir, env: state.os_env])

    {:ok, %{state | port: port}}

  end

  @impl true
  def handle_info(info = {:notify, key}, state) do
    Logger.warn("[#{__MODULE__}][#{state.os_command}] info #{inspect(info)}")
    {:noreply, %{state | pending: MapSet.delete(state.pending, key)}}
  end

  @impl true
  def handle_info(info = {:api, wpid, pid, key, arg0, message}, state) do
    Logger.warn("[#{__MODULE__}][#{state.os_command}] info #{inspect(info)}")
    # Logger.warn("[#{__MODULE__}][#{state.os_command}] sending #{inspect(<<byte_size(wpid)::integer-size(16), wpid::binary()>>)}")
    sent = :erlang.port_command(state.port, cmd = <<@api, wpid::binary(), ?#, pid::binary(), ?#, key::binary(), ?#, arg0::binary(), ?#, message::binary(), ?\n>>)
    if not sent, do: Logger.error("[#{__MODULE__}][#{state.os_command}] port_command #{inspect(cmd)}")
    {:noreply, state}
  end

  @impl true
  def handle_info(info = {:generate, quantity}, state) do
    if is_gate_open(state) do
      Logger.debug("[#{__MODULE__}][#{state.os_command}] info #{inspect(info)}")
      sent = :erlang.port_command(state.port, cmd = <<@gen, quantity, ?\n>>)
      if not sent, do: Logger.error("[#{__MODULE__}][#{state.os_command}] port_command #{inspect(cmd)}")
    end
    {:noreply, state}
  end

  @impl true
  def handle_info(info = {:create_accounts, force}, state) do
    Logger.debug("[#{__MODULE__}][#{state.os_command}] info #{inspect(info)}")
    sent = :erlang.port_command(state.port, cmd = <<@create_accounts, (if force, do: 1, else: 0), ?\n>>)
    if not sent, do: Logger.error("[#{__MODULE__}][#{state.os_command}] port_command #{inspect(cmd)}")
    {:noreply, state}
  end

  @impl true
  def handle_info({port, {:data, chunk}}, state = %{port: port}) do
    handle_data(state.previous_chunk <> chunk, state)
  end

  def handle_data(data, state) do
    Logger.debug("[#{__MODULE__}][#{state.os_command}] data #{inspect(data, limit: :infinity)}")
    case data do
      <<@master, _sid::8, key_size::16, key::binary-size(key_size), fee_denom_size::16, fee_denom::binary-size(fee_denom_size), message_size::16, message::binary-size(message_size), more_data::binary>> ->
        # if Load.is_master() do
        #   Logger.info("[#{__MODULE__}][#{state.os_command}] api lo #{inspect(message)}")
        #   send(self(),{:api, message})
        # else
        # Logger.info("[#{__MODULE__}][#{state.os_command}] api WS #{inspect(data)}")
        # Logger.info("[#{__MODULE__}][#{state.os_command}] api WS message #{inspect(message, limit: :infinity)}")
        # Logger.info("[#{__MODULE__}][#{state.os_command}] api WS message64 #{inspect(message |> Base.encode64())}")
        # Logger.info("[#{__MODULE__}][#{state.os_command}] api WS message64 decoded #{inspect(message |> Base.encode64() |> Base.decode64!(), limit: :infinity)}")
          :pg.get_local_members(WS)
          |> Enum.each(&send(&1, {:ws_send, %{api: message |> Base.encode64(), arg0: fee_denom, routing: [Load.self64(), key]}}))
        # end
        handle_data(more_data, %{state | pending: MapSet.put(state.pending, key)})
      <<@queue, sid::8, wpid_size::16, wpid::binary-size(wpid_size), pid_size::16, pid::binary-size(pid_size), key_size::16, key::binary-size(key_size), fee_denom_size::16, _fee_denom::binary-size(fee_denom_size), message_size::16, message::binary-size(message_size), more_data::binary>> ->
        Logger.debug("[#{__MODULE__}][#{state.os_command}] queue #{inspect(data)}")
        {serializer, state_serializers} = if state.serializers[sid] do
          {state.serializers[sid], state.serializers}
        else
          {:ok, pid} = DynamicSupervisor.start_child(Load.Hitter.Supervisor, {Load.Serializer, %{
            "serializer" => state.serializer, "common" => state.common}})
          {pid, Map.put(state.serializers, sid, pid)}
        end
        send(serializer, {:hit, message, [wpid, pid, key]})
        handle_data(more_data, %{state | serializers: state_serializers} )
      _ ->
        {:noreply, %{state | previous_chunk: data}}
    end
  end

  defp is_gate_open(s), do: 0 == MapSet.size(s.pending) 

end
