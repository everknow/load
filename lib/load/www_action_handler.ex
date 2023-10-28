defmodule Load.ActionHandler do

  require Logger

  def init(req = %{method: "POST"}, state) do
    {:ok, data, req} = :cowboy_req.read_body(req)

    send(Prep, {:action, data})

    req = :cowboy_req.reply(200, 
      %{"content-type" => "text/plain"},
      Jason.encode!(%{success: true}),
      req)
    {:ok, req, state}
  end
end