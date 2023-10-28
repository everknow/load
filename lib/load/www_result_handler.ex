defmodule Load.ResultHandler do

  require Logger

  def init(req = %{method: "POST"}, state) do
    {:ok, data, req} = :cowboy_req.read_body(req)

    res = :ets.take(RegResult, data)
    |> Enum.map(&(elem(&1, 1)))

    req = :cowboy_req.reply(200, 
      %{"content-type" => "text/plain"},
      res,
      req)
    {:ok, req, state}
  end
end