defmodule Sim.Poller do

  @behaviour Load.Sim

  require Logger

  import Load.Worker, only: [inc: 2, maybe_update: 1, now: 0, hit: 4]

  @impl true
  @spec init(map()) :: map()
  def init(state) do

    Logger.debug("[#{__MODULE__}] init state: #{inspect(state)}")
    %{
      interval_ms: :timer.seconds(5),
      stats_interval_ms: :timer.seconds(5),
      payload: "",
      protocol: "http",
      http_headers: [{"Content-Type", "application/json"}],    
      pending: %{}
    }
    |> Map.merge(state)
    |> Map.update(:pos_decode, &from_dec/1, &Function.capture(__MODULE__, &1, 1))
    |> Map.update(:pos_encode, &to_dec/1, &Function.capture(__MODULE__, &1, 1))
    |> Map.update(:content_decode, &Function.identity/1, &Function.capture(__MODULE__, &1, 1))
  
  end

  @impl true
  @spec run(map()) :: map()
  def run(state) do

    state
    |> process(state.pos_from)
    |> expire()

  end

  defp process(state, pos) do

    {:ok, res, state} = hit(
      String.replace(state.statement, "X XPOSX X", (if is_binary(pos), do: pos, else: pos |> state.pos_encode.())), state.http_headers,
      (if state.payload == "", do: "", else: String.replace(Jason.encode!(state.payload), "X XPOSX X", (if is_binary(pos), do: pos, else: pos |> state.pos_encode.()))),
      state)
    
    Logger.debug("response #{inspect(res)}")

    res = Jason.decode!(res)

    pos = get_in(res, state.pos_selector) |> state.pos_decode.()
    Logger.debug("[#{__MODULE__}] processing pos: #{pos}")

    state = if pos > state.pos_to do
      get_in(res, state.content_selector)
      |> Enum.reduce(process(state, pos - 1), fn content_raw, state ->
        content = content_raw |> state.content_decode.()
        Logger.debug("[#{__MODULE__}] content: #{inspect(content)}")
        case state.pending |> Map.pop(content) do
          {nil, _} ->
            state
          {{ts, [wpid, pid, key]}, pending} ->
            Logger.debug("[#{__MODULE__}] processed: #{inspect({{ts, [wpid, pid, key]}, pending})}")
            latency = now() - ts
            avg_latency = if state[:avg_latency] do
              (state.avg_latency + latency) /2
            else
              latency
            end
            if wpid != "" do
              wpid = Load.to_pid(wpid)
              send(wpid, {:ws_send, :all, %{notify: (if key != "", do: key, else: content), routing: [pid]}})
            end
            %{state | pending: pending, avg_latency: avg_latency, succeeded: state.succeeded + 1}
        end
      end)
    else
      state
    end

    if state[:pos], do: state, else: %{state | pos_to: pos} |> Map.delete(:pos)

  end

  defp expire(state) do
    now = now()
    count = Enum.count(state.pending)
    pending = state.pending |> Map.reject(fn {_k, {v, _}} -> now > v + 60000 end)
    %{state | pending: pending, failed: state.failed + (count - Enum.count(pending))}
  end

  @impl true
  def handle_message({:reg, ref, routing}, state) do
    Logger.debug("[#{__MODULE__}] reg: #{inspect(ref)} routing: #{inspect(routing)}")
    %{state | pending: state.pending |> Map.put(ref, {now(), routing})} |> inc(:requests)
  end

  def from_dec(x), do: String.to_integer(x)
  def to_dec(x), do: "#{x}"
  def from_hex("0x"<>x), do: x |> String.downcase() |> String.to_integer(16)
  def to_hex(x), do: "0x#{x |> Integer.to_string(16) |> String.downcase()}"
  def from_base64(x), do: x |> Base.decode64!() |> fn x -> :crypto.hash(:sha256, x) |> Base.encode16() end.()

end