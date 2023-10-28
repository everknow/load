defmodule Example.EchoHandler do
  def init(req = %{method: "POST"}, _state) do
    {:ok, data, req} = :cowboy_req.read_body(req)
    _req = :cowboy_req.reply(200, 
    %{"content-type" => "text/plain"},
    data, req)
  end
end
