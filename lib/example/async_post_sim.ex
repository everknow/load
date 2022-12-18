defmodule Example.AsyncPostSim do

  @behaviour Load.Sim

  require Logger

  @impl true
  def init do
    Application.get_env(:load, __MODULE__, %{})
  end

  @impl true
  def run(state) do
    payload = "example content"
    {:ok, res_payload, state} = Load.Worker.hit("POST /example/async", [], payload, state)
    ref = res_payload
    :pg.get_local_members(RefSubscribers)
    |> Enum.each(&send(&1, {:register_ref, ref}))
    Logger.debug("sim received back #{res_payload}")
    state
  end


end
