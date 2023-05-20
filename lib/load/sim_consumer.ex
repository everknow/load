defmodule Load.SimConsumer do

  @behaviour Load.Sim

  @impl true
  def init do
    more_state = %{target: "POST /example/echo"}
    more_state
  end

  @impl true
  def run(state) do
    payload = Load.Queue.pop()
    # cycle through it until it goes through  up to a max iterations put in state for retry
    {:ok, _res_payload, state} = Load.Worker.hit(state.target, [{"content-type", "application/json"}], payload, state)
    # send to stats res_payload
    state
  end


end
