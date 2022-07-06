defmodule Example.EchoRouter do
  use Plug.Router

  require Logger

  plug(Corsica, origins: "*", allow_methods: :all, allow_headers: :all)
  plug(:match)
  # plug Plug.Parsers, parsers: [:json], json_decoder: Jason
  plug(:dispatch)

  post "/example/echo" do
    {:ok, body, conn} = read_body(conn)
    send_resp(conn, 200, body)
  end

  get "/example/echo" do
    send_resp(conn, 200, "ok")
  end
end
