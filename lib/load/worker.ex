defmodule Load.Worker do

  use GenServer, restart: :transient

  require Logger

  @connect_delay 200
  @req_timeout :timer.seconds(5)

  def start_link(glob, args \\ []), do: GenServer.start_link(__MODULE__, glob ++ args |> Enum.into(%{}) )

  def init(args) do

    Logger.debug("init called with args: #{inspect(args)}")

    state = args
    |> Map.merge(args.sim.init())
    |> Map.put(:interval_ms, apply(:timer,
      Application.get_env(:load, :worker_timeunit, :seconds), [
      Application.get_env(:load, :worker_interval, 5)
    ]))
    |> Map.put(:stats_interval_ms, apply(:timer,
      Application.get_env(:load, :worker_stats_timeunit, :seconds), [
      Application.get_env(:load, :worker_stats_interval, 1)
    ]))
    |> Map.merge(Stats.empty())

    Process.send_after(self(), :connect, @connect_delay)

    {:ok, state}
  end

  def handle_info(:connect, %{host: host, port: port, opts: _opts} = state) do

    Logger.debug("connect state: #{inspect(state)}")
    # TODO handle as case
    case :gun.open(host, port) do
      {:ok, conn} ->
        resp = gun.await_up(conn)
        Logger.debug("await response: #{inspect(resp)}")
#        {:ok, _transport} = :gun.await_up(conn)
        Process.send_after(self(), :run, 0)
        {:noreply, Map.put(state, :conn, conn)}
      err ->
        Logger.debug("error: #{inspect(err)}")
        {:stop, :normal}
    end

  end


  def handle_info(:run, %{sim: sim, interval_ms: interval_ms} = state) do
    state = state
    |> sim.run()
    |> Stats.maybe_update()
    Process.send_after(self(), :run, interval_ms)
    {:noreply, state}
  end

  def hit(target, headers, payload, state) do

    %{host: host, port: port, conn: conn, opts: opts} = state

    case opts do
      %{protocols: [:http], transport: :tcp} ->
        [verb, path] = String.split(target, " ")
        case verb do
          "POST" ->
            Logger.debug("hitting http://#{host}:#{port}#{path}")
            post_ref = :gun.post(conn, "http://#{host}:#{port}#{path}", headers, payload)
            state = Map.update!(state, :requests, &(&1+1))
            handle_http_result(post_ref, state)
          _ ->
            state = Map.update!(state, :failed, &(&1+1))
            {:error , "http tcp #{verb} not_implemented", state}
        end

      %{protocols: [:ilp_packet], transport: :tcp} ->
        {:ok,conn} = :gen_tcp.connect(host, port, [:binary])
        :gen_tcp.send(conn, payload)
        state = Map.update!(state, :requests, &(&1+1))
        {:ok, "no response", state}

      err ->
        state = Map.update!(state, :failed, &(&1+1))
        {:error , "not_implemented #{err}", state}

    end
  end

  defp handle_http_result(post_ref, state = %{conn: conn}) do
    case :gun.await(conn, post_ref, @req_timeout) do
      {:response, _, code, _resp_headers} ->
        cond do
          div(code, 100) == 2 ->
            case :gun.await_body(conn, post_ref, @req_timeout) do
              {:ok, resp_payload} ->
                state = Map.update!(state, :succeeded, &(&1+1))
                {:ok, resp_payload, state}
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
