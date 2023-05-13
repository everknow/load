defmodule Example.AsyncHandler do
  def init(req = %{method: "POST"}, state) do
    {:ok, _data, req} = :cowboy_req.read_body(req)
    ref = make_ref()
    :pg.get_local_members(AsyncWS)
    |> Enum.each(&Process.send_after(&1, {:completed, ref}, :timer.seconds(2)))

    req = :cowboy_req.reply(200, 
      %{"content-type" => "text/plain"},
      inspect(ref),
      req)
  end
end
