defmodule Example.EchoHandler do
  def init(req = %{method: "POST"}, state) do
    {:ok, data, req} = :cowboy_req.read_body(req)
    req = :cowboy_req.reply(200, 
    %{"content-type" => "text/plain"},
    data,req)
  end
end
