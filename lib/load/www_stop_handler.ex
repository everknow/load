defmodule Load.StopHandler do

  require Logger

  def init(req = %{method: "GET"}, state) do

    DynamicSupervisor.which_children(Load.Connection.Supervisor)
    |> Enum.each(fn {:undefined, pid, :worker, [Load.WSClient]} ->
      send(pid, {:ws_send, :all, %{"command" => "restart_gen", "config" => %{}}})
    end)

    req = :cowboy_req.reply(200, 
      %{"content-type" => "text/plain"},
      Jason.encode!(%{success: true}),
      req)
    {:ok, req, state}
  end
end