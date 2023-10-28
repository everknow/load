defmodule Sim.Poller do

  @behaviour Load.Sim

  require Logger

  # group: Poller 
  # "pos_selector" => ["block", "header", "height"],
  # "pos_decode" => "from_dec", # "from_hex"
  # "pos_encode" => "to_hex"
  # "content_selector" => ["block", "data", "txs"], ["result", "transactions"]
  # "content_decode" => "from_base64", # "noop"
  # "target" => "GET /cosmos/base/tendermint/v1beta1/blocks/X XPOSX X", "POST /"
  # "payload" => "{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["X XPOS X X", false],"id":1}"
  # "host" => System.get_env("HOST"),
  # "port" => 1317,
  # "pos_from" => "latest",
  # "pos_to" => 1,
  @impl true
  @spec init(map()) :: map()
  def init(state) do

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
  def handle_message({:register, ref}, state) do
    %{state | pending: state.pending |> Map.put(ref, now())}
  end

  @impl true
  @spec run(map()) :: map()
  def run(state) do

    pos = if state.pos, do: state.pos, else: state.pos_from

    {:ok, res, state} = Load.Worker.hit(
      String.replace(state.statement, "X XPOSX X", pos |> state.pos_encode.()), state.http_headers,
      String.replace(state.payload, "X XPOSX X", pos |> state.pos_encode.()), state)

    res = Jason.decode!(res)

    pos = get_in(res, state.pos_selector) |> state.pos_decode.()
    Logger.info("[#{__MODULE__}] processing pos: #{pos}")

    if pos > state.pos_to do
      run(Map.put(state, :pos, "#{pos - 1}"))
      |> Enum.reduce(fn content_raw, state ->
        content = content_raw |> state.content_decode.()
        case state.pending |> Map.pop(content) do
          {nil, _} ->
            state
          {ts, pending} ->
            Logger.warn("[#{__MODULE__}] processed: #{inspect({ts, pending})}")
            latency = now() - ts
            avg_latency = if state[:avg_latency] do
              (state.avg_latency + latency) /2
            else
              latency
            end
            %{state | pending: pending, avg_latency: avg_latency, succeeded: state.succeeded + 1}
        end
      end, get_in(res, state.content_selector))
    else
      state
    end

  end

  defp now, do: DateTime.utc_now |> DateTime.to_unix(:millisecond)
  defp from_dec(x), do: String.to_integer(x)
  defp to_dec(x), do: "#{x}"
  def from_hex("0x"<>x), do: x |> String.downcase() |> String.to_integer(16)
  def to_hex(x), do: "0x#{x |> Integer.to_string(16) |> String.downcase()}"
  def from_base64(x), do: x |> Base.decode64!() |> fn x -> :crypto.hash(:sha256, x) |> Base.encode16() end.()

end