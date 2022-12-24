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
      opts: %{retry: 0, ws_opts: %{keepalive: :timer.seconds(20), silence_pings: true}}
    })
    |> Map.merge(args.sim.init())
    |> Map.merge(Stats.empty())

    if state[:group], do: :pg.join(state.group, self())

    Process.send_after(self(), :connect, @connect_delay)

    {:ok, state}
  end

  @impl true
  def handle_info(:connect, %{"host" => host, "port" => port} = state) do
    Logger.debug("connect state: #{inspect(state)}")
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

  def handle_info(:run, %{sim: sim, interval_ms: interval_ms} = state) do
    state = state
    |> sim.run()
    |> Stats.maybe_update()
    Process.send_after(self(), :run, interval_ms)
    {:noreply, state}
  end

  def handle_info(message, %{sim: sim} = state) do
    if Keyword.has_key?(sim.__info__(:functions), :handle_info) do
      {:noreply, sim.handle_message(message, state)}
    else
      {:noreply, state}
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

end
