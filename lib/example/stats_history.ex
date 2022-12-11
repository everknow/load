defmodule Example.StatsHistory do
  use GenServer

  @impl true
  def init(args) do
    :erlang.register(__MODULE__, self())
    Load.subscribe(self())
    state = args
    |> Map.merge(empty())

    {:ok, state}
  end

  @impl true
  def handle_info({:update, stats}, state), do: {:noreply, %{state | history: [stats | state.history]}}

  @impl true
  def handle_call(:get , _from, state), do: {:reply, state, state}

  def empty, do: %{history: []}

  def get, do: GenServer.call(__MODULE__, :get)

end
