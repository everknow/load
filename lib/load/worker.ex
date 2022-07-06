defmodule Load.Worker do
  use GenServer, restart: :transient

  require Logger

  @connect_delay 200
  @req_timeout :timer.seconds(5)

  def start_link(glob, args \\ []),
    do: GenServer.start_link(__MODULE__, (glob ++ args) |> Enum.into(%{}))

  def init(args) do
    Logger.debug("init called with args: #{inspect(args)}")

    state =
      args
      |> Map.merge(args.sim.init())
      |> Map.put(:stats_entries, 0)
      |> Map.put(
        :interval_ms,
        apply(:timer, Application.get_env(:load, :worker_timeunit, :seconds), [
          Application.get_env(:load, :worker_interval, 5)
        ])
      )
      |> Map.put(
        :stats_interval_ms,
        apply(:timer, Application.get_env(:load, :worker_stats_timeunit, :seconds), [
          Application.get_env(:load, :worker_stats_interval, 1)
        ])
      )
      |> Map.merge(Stats.empty())

    Process.send_after(self(), :connect, @connect_delay)

    {:ok, state}
  end

  def handle_info(:connect, %{host: host, port: port, opts: _opts} = state) do
    # TODO handle as case
    {:ok, conn} = :gun.open(host, port)
    {:ok, _transport} = :gun.await_up(conn)

    Process.send_after(self(), :run, 0)

    {:noreply, Map.put(state, :conn, conn)}
  end

  def handle_info(:run, %{sim: sim, interval_ms: interval_ms} = state) do
    Logger.debug("Worker.run/2")

    state =
      state
      |> sim.run()
      |> Stats.maybe_update()

    Process.send_after(self(), :run, interval_ms)

    {:noreply, state}
  end

  def handle_info(:exit, state) do
    {:stop, :normal, state}
  end

  def hit(target, headers, payload, state) do
    %{host: host, port: port, conn: conn, stats_entries: stats_entries, opts: opts} = state

    case opts do
      %{protocols: [:http], transport: :tcp} ->
        [verb, path] = String.split(target, " ")

        case verb do
          "POST" ->
            Logger.debug("hitting http://#{host}:#{port}#{path}")
            post_ref = :gun.post(conn, "http://#{host}:#{port}#{path}", headers, payload)
            g = :gun.await(conn, post_ref, @req_timeout)
            {:ok, resp_payload} = handle_http_result(g, post_ref, state)
            state = Map.put(state, :stats_entries, stats_entries + 1)
            {:ok, resp_payload, state}

          _ ->
            {:error, "http tcp #{verb} not_implemented"}
        end

      %{protocols: [:ilp_packet], transport: :tcp} ->
        {:ok, conn} = :gen_tcp.connect(host, port, [:binary])
        :gen_tcp.send(conn, payload)
        {:ok, "no response", state}

      _ ->
        {:error, "not_implemented"}
    end
  end

  defp handle_http_result({:response, _, code, _resp_headers}, post_ref, %{conn: conn}) do
    cond do
      div(code, 100) == 2 ->
        :gun.await_body(conn, post_ref, @req_timeout)

      # this is returned when incorrect packet is sent
      # we will allow this for now as we want to continue
      # load testing even when receiving a Reject
      :demo ->
        :gun.await_body(conn, post_ref, @req_timeout)

        # :else ->
        #   {:error, "response code #{code}"}
    end
  end

  defp handle_http_result(
         reason,
         _,
         %{sleep_time: sleep_time, stats_errors: stats_errors} = state
       ) do
    Logger.error("Error (#{inspect(self())}) #{inspect(reason)}")

    Process.send_after(self(), :loop, sleep_time)

    state = Map.put(state, :stats_errors, stats_errors + 1)
    {:noreply, state}
  end
end

# this is for websocket?
# case :gun.await_up(conn, @gun_timeout) do
#     {:ok, _} ->
#         conn
#     {:error, :timeout} ->
#         :timer.sleep(:timer.seconds(2))
#         create_connection(host_ip, port, http_opts, max_retries - 1)
#     error ->
#       Logger.error("Could not connect to host:#{inspect(host_ip)} port:#{inspect(port)} due to:#{inspect(error)}")
#         error
# end

# def handle_info(:get_ip, %{host: host} = state) do

#   case :inet.getaddr(host, :inet) do

#     {:ok, ip} ->
#       Process.send_after(self(), :connect, 0)
#       {:noreply, Map.put(state, :ip, ip)}

#     {:error, reason} ->
#       Logger.error("[#{__MODULE__}] init failed for host:#{inspect(host)} due to:#{inspect(reason)}")
#       Process.send_after(self(), :get_ip, @connect_delay)
#   end

# end
