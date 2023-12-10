defmodule Load.CreateAccountsHandler do

  require Logger

  def init(req = %{method: "GET"}, state) do
    qs = :cowboy_req.qs(req)
    force = case qs do
      %{"force" => "true"} ->
        true
      _ ->
        false
    end
    DynamicSupervisor.which_children(Load.Connection.Supervisor)
    |> Enum.each(fn {:undefined, pid, :worker, [Load.WSClient]} ->
      send(pid, {:ws_send, :all, %{"command" => "create_accounts", "force" => force}})
    end)

    req = :cowboy_req.reply(200, 
      %{"content-type" => "text/plain"},
      Jason.encode!(%{sent: true}),
      req)
    {:ok, req, state}
  end
end