defmodule Load.Serializer do

  use GenServer

  require Logger

  defdelegate inc(state, k, amount \\ 1), to: Load.Worker, as: :inc

  def start_link(glob, args \\ []), do: GenServer.start_link(__MODULE__, glob ++ args |> Enum.into(%{}) )

  # host |> String.to_charlist()
  # ws |> String.to_charlist()
  # headers
  @impl true
  def init(args) do

    state = args
    |> Map.merge(%{
      host: args["serializer"]["hit_host"] |> to_charlist(),
      port: args["serializer"]["hit_port"],
      protocol: args["serializer"]["protocol"]
    })
    |> then(fn m -> if args["statement"] do
        [verb, path] = String.split(args["statement"], " ")
        m |> Map.merge(%{verb: verb, path: path})
      else
        m
      end
    end)
    |> Map.drop("serializer")

    {:ok, state}
  end

  @impl true
  def handle_info({:hit, payload}, state) do
    state = if state.conn, do: state, else: connect(state)

    if state.conn do
      case state.protocol do
        
        "http_ws" ->
          :ok = :gun.ws_send(state.conn, state.stream_ref, payload)
          {:noreply, state}
        
        "http" ->
          {latency, res} = :timer.tc(fn ->
            post_ref = apply(:gun, state.verb, [state.conn, state.path, state.headers] ++ (if state.verb == :get, do: [], else: [payload]))
            Load.Worker.handle_http_result(post_ref, state |> inc(:requests))
          end)
          case res do
            {:ok, _data, state} -> {:noreply, Map.update(state, :avg_latency, latency/1000, &((&1+latency/1000)/2)) |> Load.Worker.maybe_update()}
            _ -> {:noreply, state |> Load.Worker.maybe_update()}
          end

        "raw" ->
          :gen_tcp.send(state.conn, payload)
          {:noreply, state |> inc(:requests) |> Load.Worker.maybe_update()}

        _ ->
          Logger.error("[#{__MODULE__}] unknown protocol #{state.protocol}")
          {:noreply, state |> inc(:failed) |> Load.Worker.maybe_update()}

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
                if state.ws do
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