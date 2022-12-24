defmodule Example.AsyncRouter do
  use Plug.Router

  require Logger

  plug :match
  plug :dispatch

  post "/example/async" do
    {:ok, _body, conn} = read_body(conn)
    ref = make_ref()
    :pg.get_local_members(AsyncWS)
    |> Enum.each(&send(&1, {:completed, ref}))
    send_resp(conn, 200, inspect(ref))
  end

end
