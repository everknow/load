defmodule Load.ProxyHandler do

  require Logger

  @req_timeout :timer.seconds(5)

  def init(req = %{method: "POST"}, state) do
    {:ok, data, req} = :cowboy_req.read_body(req)
    h = :cowboy_req.headers(req)
    {:ok, conn} = :gun.open(h["fw_host"] |> to_charlist(), h["fw_port"] |> String.to_integer(), %{protocols: [:http], transport: :tcp})
    {:ok, :http} = :gun.await_up(conn)
    ref = case h["fw_method"] do
      "post" -> 
        :gun.post(conn, h["fw_path"], [{"Content-Type", "application/json"}], data)
      _ -> 
        :gun.get(conn, h["fw_path"], [{"Content-Type", "application/json"}])
    end
    {:response, _, _code, _resp_headers} = :gun.await(conn, ref, @req_timeout)
    {:ok, payload} = :gun.await_body(conn, ref, @req_timeout)

    req = :cowboy_req.reply(200, 
      %{"content-type" => "application/json"},
      payload,
      req)
    {:ok, req, state}
  end
end