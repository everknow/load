defmodule Load.StartHandler do
  def init(req = %{method: "POST"}, state) do
    {:ok, data, req} = :cowboy_req.read_body(req)
    config = Jason.decode!(data)
    
    Load.connect(["localhost"])

    :timer.sleep(3000)

    Load.setup(config)

    Load.autoscale(config)
    # Load.scale(1, Sim.Poller)

    req = :cowboy_req.reply(200, 
      %{"content-type" => "text/plain"},
      Jason.encode!(%{success: true}),
      req)
    {:ok, req, state}
  end
end