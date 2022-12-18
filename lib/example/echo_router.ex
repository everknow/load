defmodule Example.EchoRouter do
  use Plug.Router

  require Logger

  plug :match
  plug :dispatch

  post "/example/echo" do
    {:ok, body, conn} = read_body(conn)
    send_resp(conn, 200, body)
  end

end
