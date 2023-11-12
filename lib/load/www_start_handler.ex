defmodule Load.StartHandler do

  require Logger

  def init(req = %{method: "POST"}, state) do
    {:ok, data, req} = :cowboy_req.read_body(req)
    config = Jason.decode!(data)
    Logger.debug("[#{__MODULE__}] init #{inspect(config)}")
    
    :timer.sleep(3000)
    
    # Load.configure(config |> Map.take(["gen"]))

    Load.autoscale(config)

    req = :cowboy_req.reply(200, 
      %{"content-type" => "text/plain"},
      Jason.encode!(%{success: true}),
      req)
    {:ok, req, state}
  end
end