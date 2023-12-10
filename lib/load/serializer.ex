defmodule Load.Serializer do

  use GenServer

  require Logger

  import Load.Worker, only: [inc: 2, maybe_update: 1, now: 0]

  @req_timeout :timer.seconds(5)

  def start_link(args, glob \\ []) do
    Logger.debug("[#{__MODULE__}] statr_link #{inspect(glob)} #{inspect(args)}") 
    GenServer.start_link(__MODULE__, (glob |> Enum.into(%{})) |> Map.merge(args)  )
  end

  # host |> String.to_charlist()
  # ws |> String.to_charlist()
  # headers
  @impl true
  def init(args) do

    state = args
    |> Map.merge(%{
      host: args["common"]["hit_host"] |> to_charlist(),
      port: args["common"]["hit_port"],
      protocol: args["serializer"]["protocol"],
      pos_selector: args["serializer"]["pos_selector"],
      conn: nil,
      last_ms: now(),
      opts: %{protocols: [:http], transport: :tcp},
      http_headers: [{"Content-Type", "application/json"}],
      stats_interval_ms: :timer.seconds(5),
      sim: Submitted
    })
    |> then(fn m -> if args["serializer"]["statement"] do
        [verb, path] = String.split(args["serializer"]["statement"], " ")
        m |> Map.merge(%{verb: verb |> String.to_existing_atom(), path: path})
      else
        m
      end
    end)
    |> Map.merge(Stats.empty())
    |> Map.drop(["serializer", "common"])

    {:ok, state}
  end

  @impl true
  def handle_info({:gun_down, _, :http, :closed, []}, state) do
    {:noreply, %{state | conn: nil}}
  end

  @impl true
  def handle_info({:gun_up, _, :http}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info({:hit, payload, routing}, state) do
    Logger.info("[#{__MODULE__}] handle_info payload: #{inspect(payload)} routing: #{inspect(routing)} state: #{inspect(state)}")
    state = if state.conn, do: state, else: connect(state)

    if state.conn do
      case state.protocol do
        
        "http_ws" ->
          :ok = :gun.ws_send(state.conn, state.stream_ref, payload)
          {:noreply, state}
        
        "http" ->
          {latency, res} = :timer.tc(fn ->
            post_ref = apply(:gun, state.verb, [state.conn, state.path, state.http_headers] ++ (if state.verb == :get, do: [], else: [payload]))
            state = state |> inc(:requests)
            case :gun.await(state.conn, post_ref, @req_timeout) do
              {:response, _, code, _resp_headers} ->
                cond do
                  div(code, 100) == 2 ->
                    case :gun.await_body(state.conn, post_ref, @req_timeout) do
                      {:ok, payload} ->
                        ref = get_in(Jason.decode!(payload), state.pos_selector)
                        Logger.info("[#{__MODULE__}] ref: #{inspect(ref)} routing: #{inspect(routing)}")
                        :pg.get_local_members(WS)
                        |> Enum.each(&send(&1, {:ws_send, %{reg: ref, routing: routing}}))
                        {:ok, payload, state |> inc(:succeeded)}
                      err ->
                        {:error, err, state |> inc(:failed) }
                    end
        
                  :else ->
                    {:error, "response code #{code}", state |> inc(:failed)}
                end
              err->
                {:error, err, state |> inc(:failed)}
            end
          end)
          case res do
            {:ok, _data, state} -> {:noreply, Map.update(state, :avg_latency, latency/1000, fn avg_latency ->
              if avg_latency do
                (avg_latency + latency/1000) / 2
              else
                latency/1000
              end
            end ) |> maybe_update()}
            _ -> {:noreply, state |> maybe_update()}
          end

        "raw" ->
          :gen_tcp.send(state.conn, payload)
          {:noreply, state |> inc(:requests) |> maybe_update()}

        _ ->
          Logger.error("[#{__MODULE__}] unknown protocol #{state.protocol}")
          {:noreply, state |> inc(:failed) |> maybe_update()}

      end

    else
      {:stop, :normal, state}
    end

  end

  defp connect(state) do
    case state.protocol do
    
      "http" ->
        case :gun.open(state.host, state.port, state.opts) do
          {:ok, conn} ->
            case :gun.await_up(conn) do
              {:ok, :http} ->
                if state[:ws] do
                  stream_ref = :gun.ws_upgrade(conn, state.ws)
                  state |> Map.merge(%{conn: conn, stream_ref: stream_ref})
                else
                  state |> Map.merge(%{conn: conn})
                end
              err ->
                Logger.error("[#{__MODULE__}] gun.await_up #{inspect(err)}")
                state
            end
          err ->
            Logger.warn("[#{__MODULE__}] gun.open http #{inspect(err)}")
            state
        end

      "raw" ->
        case :gun.open(state.host, state.port) do
          {:ok, conn} ->
            state |> Map.merge(%{conn: conn})
          err ->
            Logger.warn("[#{__MODULE__}] gun.open raw #{inspect(err)}")
            state
        end

    end
  end

end