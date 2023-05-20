defmodule Load.Container do

  use GenServer

  require Logger

  @impl true
  def init(args) do

    state = args
    |> Map.merge(%{
      port: :ok,
      previous_chunk: ""
    })

    port = :erlang.open_port({:spawn, state.os_command}, [{:cd, state.os_dir}, :binary, :exit_status])
    sent = :erlang.port_command(port, state.start_command)
    if not sent, do: Logger.error("could not send to port")

    {:ok, %{state | port: port, count: state.count}}

  end

  @impl true
  def handle_info({:prep_accounts, account_ids}, state) do
    sent = :erlang.port_command(state.port, account_ids)
    if not sent, do: Logger.error("could not send :prep_accounts to port")
    {:noreply, state}
  end

  @impl true
  def handle_info({port, {:data, chunk}}, state = %{port: port}) do
    handle_data(state.previous_chunk <> chunk, state)
  end

  def handle_data(data, state) do
    if state.count > 0 do
      {messages, more_data} = String.split(data, "\n") |> Enum.split(-1)
      :pg.get_local_members(WS)
      |> Enum.each(&send(&1, {:prep_accounts, Enum.join(messages, "\n")<>"\n"}))
      {:noreply, %{state | previous_chunk: more_data}}
    else
      case data do
        <<message_size::16, message::binary-size(message_size), more_data::binary>> ->
          Load.Queue.push(message |> IO.inspect())
          handle_data(more_data, state)
          {:noreply, %{state | previous_chunk: more_data}}
        _ ->
          {:noreply, %{state | previous_chunk: data}}
      end
    end
  end


end
