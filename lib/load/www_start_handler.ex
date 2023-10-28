defmodule Load.StartHandler do

  require Logger

  def init(req = %{method: "POST"}, state) do
    {:ok, data, req} = :cowboy_req.read_body(req)
    config = Jason.decode!(data)
    Logger.warn("#{inspect(config)}")
    
    :timer.sleep(3000)
    
    Load.configure(config |> Map.take(["gen"]))

    Load.autoscale(config |> Map.drop(["gen"]))

    req = :cowboy_req.reply(200, 
      %{"content-type" => "text/plain"},
      Jason.encode!(%{success: true}),
      req)
    {:ok, req, state}
  end
end