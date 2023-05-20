defmodule Load.Queue do
  use GenServer

  @impl true
  def init(args) do

    state = args
    |> Map.merge(%{
      queued: :queue.new()
    })

    {:ok, state}
  end

  @impl true
  def handle_cast({:push, msg}, state) do
    {:noreply, %{state | queued: :queue.in(msg, state.queued)}}
  end
  
  @impl true
  def handle_call(:pop, _from, state) do
    case :queue.out(state.queued) do
      {{:value, msg}, more} ->
        {:reply, [msg], %{state | queued: more}}
      {:empty, more} ->
        {:reply, [], %{state | queued: more}}
      end
  end

  def push(msg) do
    GenServer.cast(Queue, {:push, msg})
  end

  def pop() do
    GenServer.call(Queue, :pop)
  end


end