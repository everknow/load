defmodule Example.EchoSim do
  @behaviour Load.Sim

  require Logger

  @impl true
  def init do
    %{
      host: Application.get_env(:net_load, :host, "localhost") |> String.to_charlist(),
      port: Application.get_env(:net_load, :port, "8888") |> String.to_integer(),
      opts: %{protocols: [:http], transport: :tcp}
    }
  end

  @impl true
  def run(state) do
    payload = "example content"
    {:ok, res_payload, state} = Load.Worker.hit("POST /example/echo", [], payload, state)
    Logger.debug("sim received back #{res_payload}")
    state
  end
end
