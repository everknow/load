defmodule Load.UploadHandler do

  require Logger

  def init(req = %{method: "POST"}, state) do
    {:ok, data, req} = :cowboy_req.read_body(req)

    file = (:code.priv_dir(:load) |> List.to_string()) <> "/uploaded.py"
    File.write(file, data)

    DynamicSupervisor.which_children(Load.Connection.Supervisor)
    |> Enum.each(fn {:undefined, pid, :worker, [Load.WSClient]} ->
      send(pid, {:ws_send, :all, %{"command" => "restart_gen", "config" => %{"os_command" => "python3 uploaded.py"}}})
    end)

    req = :cowboy_req.reply(200, 
      %{"content-type" => "text/plain"},
      Jason.encode!(%{success: true}),
      req)
    {:ok, req, state}
  end
end