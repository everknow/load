defmodule Load.HealthHandler do
  def init(req0 = %{method: "GET"}, state) do
    req = :cowboy_req.reply(200, %{
        "content-type" => "text/plain"
    }, "Hello World!", req0)
    {:ok, req, state}
  end
end