defmodule Load.WSClient do

  use GenServer, restart: :transient

  require Logger

  def start_link(glob, args \\ []), do: GenServer.start_link(__MODULE__, glob ++ args |> Enum.into(%{}))

  @impl true
  def init(args) do
    Process.send_after(self(), :connect, :timer.seconds(1))
    state = args
    {:ok, state}
  end

  @impl true
  def handle_info(:connect, state) do
    {:ok, conn} = :gun.open(state.address |> to_charlist(), _port = 8888, %{retry: 0, ws_opts: %{keepalive: :timer.seconds(20), silence_pings: true} })
    {:ok, _transport} = :gun.await_up(conn)
    stream_ref = :gun.ws_upgrade(conn, "/ws" |> to_charlist())
    {:noreply, state |> Map.put(:conn, conn) |> Map.put(:stream_ref, stream_ref)}
  end

  @impl true
  def handle_info({:gun_ws, _conn, _, {:text, message}}, state) do
    case Jason.decode!(message) do
      %{"ok" => "ok"} ->
        Logger.info("cool good response")
      %{"stats" => stats} ->
        :pg.get_local_members(Global)
        |> Enum.each(&send(&1, {:update, stats |> Map.new(fn {k, v} -> {String.to_atom(k), v} end)}))
      _ ->
        Logger.error("[#{__MODULE__}] invalid")
    end
    {:noreply, state}
  end

  @impl true
  def handle_info({:gun_down, conn, _ws, _closed, _, _}, state) do
    Logger.warn("[#{__MODULE__}] Socket down #{state.address}")
    :ok = :gun.close(conn)
    :ok = :gun.flush(conn)
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:gun_ws, conn, _ws, {:close, _, ""}}, state) do
    Logger.warn("[#{__MODULE__}] Socket closed #{state.address}")
    :ok = :gun.close(conn)
    :ok = :gun.flush(conn)
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:gun_upgrade, _conn, _mon, _type, _info}, state) do
    Logger.warn("[#{__MODULE__}] Connection upgraded")
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warn("[#{__MODULE__}] unknown info received #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def handle_call(:get_address, _from, state) do
    {:reply, state.address, state}
  end

  @impl true
  def handle_cast({:ws_send, address, message}, %{stream_ref: stream_ref} = state) do
    if address == :all or address == state.address do
      :ok = :gun.ws_send(state.conn, stream_ref, {:text, Jason.encode!(message)})
    end
    {:noreply, state}
  end

end
