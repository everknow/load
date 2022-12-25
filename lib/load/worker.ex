defmodule Load.Worker do

  use GenServer, restart: :transient

  require Logger

  @connect_delay 200
  @req_timeout :timer.seconds(5)

  def start_link(glob, args \\ []), do: GenServer.start_link(__MODULE__, glob ++ args |> Enum.into(%{}) )

  @impl true
  def init(args) do

    Logger.debug("init called with args: #{inspect(args)}")

    state = args
    |> Map.merge(%{
      conn: nil,
      stream_ref: nil,
      # opts: %{retry: 0, ws_opts: %{keepalive: :timer.seconds(20), silence_pings: true}}
      opts: %{protocols: [:http], transport: :tcp},
      last_ms: now()
    })
    |> Map.merge(args.sim.init())
    |> Map.merge(Stats.empty())

    if state[:group], do: :pg.join(state.group, self())

    Process.send_after(self(), :connect, @connect_delay)

    {:ok, state}
  end

  @impl true
  def handle_info(:connect, %{"host" => host, "port" => port} = state) do
    case state["protocol"] do
      "http" ->
        case :gun.open(host |> String.to_charlist(), port, state.opts) do
          {:ok, conn} ->
            case :gun.await_up(conn) do
              {:ok, :http} ->
                Process.send_after(self(), :run, 0)
                if state["ws"] do
                  stream_ref = :gun.ws_upgrade(conn, state["ws"] |> to_charlist())
                  {:noreply, %{state | conn: conn, stream_ref: stream_ref}}
                else
                  {:noreply, %{state | conn: conn}}
                end
              err ->
                Logger.warn("gun.await_up: #{inspect(err)}")
                {:stop, :normal, state}
            end
          err ->
            Logger.warn("gun.open http: #{inspect(err)}")
            {:stop, :normal, state}
        end
      "raw" ->
        case :gun.open(host |> String.to_charlist(), port) do
          {:ok, conn} ->
            Process.send_after(self(), :run, 0)
            {:noreply, %{state | conn: conn}}
          err ->
            Logger.warn("gun.open raw: #{inspect(err)}")
            {:stop, :normal, state}
        end
    end
  end

  def handle_info(:run, state) do
    state = state
    |> state.sim.run()
    |> maybe_update()
    if state["interval_ms"], do:
      Process.send_after(self(), :run, state["interval_ms"])
    {:noreply, state}
  end

  def handle_info(message, %{sim: sim} = state) do
    if Keyword.has_key?(sim.__info__(:functions), :handle_info) do
      {:noreply, sim.handle_message(message, state)}
    else
      {:noreply, state}
    end
  end

  defp maybe_update(%{"stats_interval_ms" => stats_interval_ms} = state) do
    dest = Local
    now = now()
    duration = now - state.last_ms
    if duration > stats_interval_ms do
      :pg.get_local_members(dest)
      |> Enum.each(&send(&1, {:update, __MODULE__, state |> Map.take(Map.keys(Stats.empty()))}))
      Map.merge(%{state | last_ms: now}, Stats.empty())
    else
      state
    end
  end

  def hit(target, headers, payload, %{conn: conn} = state) do
    case state["protocol"] do
      "http" ->
        if state["ws"] do
          :ok = :gun.ws_send(conn, state.stream_ref, payload)
          {:ok, nil, state}
        else
          [verb, path] = String.split(target, " ")
          case verb do
            "POST" ->
              Logger.debug("hitting http://#{state["host"]}:#{state["port"]}#{path}")
              post_ref = :gun.post(conn, "#{path}", headers, payload)
              state = Map.update!(state, :requests, &(&1+1))
              handle_http_result(post_ref, state)
            _ ->
              state = Map.update!(state, :failed, &(&1+1))
              {:error , "http tcp #{verb} not_implemented", state}
          end
        end
      "raw" ->
        :gen_tcp.send(conn, payload)
        state = Map.update!(state, :requests, &(&1+1))
        {:ok, nil, state}
      _ ->
        state = Map.update!(state, :failed, &(&1+1))
        {:error , "unknown protocol #{state[:protocol]}", state}
    end
  end

  defp handle_http_result(post_ref, state = %{conn: conn}) do
    case :gun.await(conn, post_ref, @req_timeout) do
      {:response, _, code, _resp_headers} ->
        cond do
          div(code, 100) == 2 ->
            case :gun.await_body(conn, post_ref, @req_timeout) do
              {:ok, payload} ->
                Map.get(state, :payload_process_fun, fn payload, _code, state ->
                  {:ok, payload, Map.update!(state, :succeeded, &(&1+1))}
                end).(payload, code, state)
              err ->
                state = Map.update!(state, :failed, &(&1+1))
                {:error, err, state}
            end

          :else ->
            state = Map.update!(state, :failed, &(&1+1))
            {:error, "response code #{code}", state}
        end
      err->
        state = Map.update!(state, :failed, &(&1+1))
        {:error, err, state}
    end

  end

  @impl true
  def terminate(_reason, state) do
    if state[:group], do: :pg.leave(state.group, self())
    :normal
  end

  def now, do: DateTime.utc_now |> DateTime.to_unix(:millisecond)

end
