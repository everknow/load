defmodule Load.StatsHandler do

  require Logger

  def init(req = %{method: "GET"}, state) do

    global = :sys.get_state(GlobalStats)
    stats = global.stats
    |> Enum.map(&rk/1)
    |> Enum.into(%{history: (global.history || []) 
      |> Enum.map(fn e -> e |> Tuple.to_list() |> Enum.drop(1) end)
      |> Enum.concat()
      |> Enum.map(fn e -> e |> Enum.map(&rk/1) |> Enum.into(%{}) end)
      })

    Logger.debug("[#{__MODULE__}] init #{inspect(stats)}")
    
    req = :cowboy_req.reply(200, %{
      "content-type" => "application/json"
      },
      Jason.encode!(stats),
      req)
    {:ok, req, state}
  end

  def rk({k,v}) do
    case k do
      Sim.Poller -> {"processed", v}
      Submitted -> {"submitted", v}
    end
  end
end