defmodule Load.Worker do

  use GenServer, restart: :transient

  require Logger

  @default_connect_delay 200
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

    connect_delay =
      if state["interval_ms"] do
        :rand.uniform(state["interval_ms"])
      else
        @default_connect_delay
      end

    Process.send_after(self(), :connect, connect_delay)

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
    if state["interval_ms"], do:
      Process.send_after(self(), :run, state["interval_ms"])
    state = state
    |> state.sim.run()
    |> maybe_update()
    {:noreply, state}
  end

  def handle_info(message, %{sim: sim} = state) do
    has_handler = sim.__info__(:functions) |> Enum.member?({:handle_message, 2})
    if has_handler do
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
      |> Enum.each(&send(&1, {:update, %{"#{state.sim}": state |> Map.take(Map.keys(Stats.empty()))}}))
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
              Logger.debug("POST hitting http://#{state["host"]}:#{state["port"]}#{path}")
              {latency, res} = :timer.tc(fn ->
                post_ref = :gun.post(conn, "#{path}", headers, payload)
                handle_http_result(post_ref, state |> inc(:requests))
              end)
              case res do
                {:ok, p, s} when s.avg_latency -> {:ok, p, %{s | avg_latency: (s.avg_latency + latency/1000) / 2}}
                {:ok, p, s} -> {:ok, p, %{s | avg_latency: latency/1000}}
                pass -> pass
              end
            "GET" ->
              Logger.debug("GET hitting http://#{state["host"]}:#{state["port"]}#{path}")
              {latency, res} = :timer.tc(fn ->
                post_ref = :gun.get(conn, "#{path}", headers)
                handle_http_result(post_ref, state |> inc(:requests))
              end)
              case res do
                {:ok, p, s} when s.avg_latency -> {:ok, p, %{s | avg_latency: (s.avg_latency + latency/1000) / 2}}
                {:ok, p, s} -> {:ok, p, %{s | avg_latency: latency/1000}}
                pass -> pass
              end
            _ ->
              {:error , "http tcp #{verb} not_implemented", state |> inc(:failed)}
          end
        end
      "raw" ->
        :gen_tcp.send(conn, payload)
        {:ok, nil, state |> inc(:requests)}
      _ ->
        {:error , "unknown protocol #{state[:protocol]}", state |> inc(:failed)}
    end
  end

  def handle_http_result(post_ref, state = %{conn: conn}) do
    case :gun.await(conn, post_ref, @req_timeout) do
      {:response, _, code, _resp_headers} ->
        cond do
          div(code, 100) == 2 ->
            case :gun.await_body(conn, post_ref, @req_timeout) do
              {:ok, payload} ->
                Map.get(state, :payload_process_fun, fn payload, _code, state ->
                  is_poller = state.sim |> :erlang.atom_to_binary() |> String.ends_with?("Poller")
                  {:ok, payload, (if is_poller, do: state, else: state |> inc(:succeeded))}
                end).(payload, code, state)
              err ->
                {:error, err, state |> inc(:failed) }
            end

          :else ->
            {:error, "response code #{code}", state |> inc(:failed)}
        end
      err->
        {:error, err, state |> inc(:failed)}
    end

  end

  @impl true
  def terminate(_reason, state) do
    if state[:group], do: :pg.leave(state.group, self())
    :normal
  end

  def now, do: DateTime.utc_now |> DateTime.to_unix(:millisecond)

  def inc(state, k, amount \\ 1) when is_integer(amount), do: state |> Map.update!(k, &(&1+amount))

end
