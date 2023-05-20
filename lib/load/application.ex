defmodule Load.Application do
  use Application

  @impl true
  @spec start(any, any) :: {:error, any} | {:ok, pid}
  def start(_type, _args) do

    case Application.get_env(:load, :config_mod) do
      nil ->
        :ok
      config_mod ->
        config_mod.init()
    end


  {:ok, _} = :cowboy.start_clear(:my_http_listener,
      [{:port,  Application.get_env(:load, :ws_port, 8888)}],
      %{env: %{dispatch: :cowboy_router.compile(dispatch())}}
  )

    children = [
      {DynamicSupervisor, strategy: :one_for_one, name: Load.Worker.Supervisor}, #, extra_arguments: [[a: :b]]}
      {DynamicSupervisor, strategy: :one_for_one, name: Load.Connection.Supervisor},
      %{id: :pg, start: {:pg, :start_link, []}},
      %{id: IdSequence, start: {GenServer, :start_link, [Load.Id.Sequence, %{}, [name: IdSequence]]}},
      %{id: IdAllocated, start: {GenServer, :start_link, [Load.Id.Allocated, %{}, [name: IdAllocated]]}},
      %{id: Scaler, start: {GenServer, :start_link, [Load.Scaler, %{}, [name: Scaler]]}},
      %{id: LocalStats, start: {GenServer, :start_link, [Stats, %{group: Local}, [name: LocalStats]]}},
      %{id: GlobalStats, start: {GenServer, :start_link, [Stats, %{group: Global}, [name: GlobalStats]]}},
      %{id: Queue, start: {GenServer, :start_link, [Load.Queue, %{}, [name: Queue]]}}
    ]
    ++ Application.get_env(:load, :injected_children, [])

    opts = [strategy: :one_for_one, name: Load.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def dispatch do
    [
      {:_,
       [
         {"/ws", Load.WSHandler, []},
         {"/start", Load.StartHandler, []},
         {"/health", Load.HealthHandler, []},
         {"/example/echo", Plug.Cowboy.Handler, {Example.EchoRouter, []}},
         {"/example/async", Plug.Cowboy.Handler, {Example.AsyncRouter, []}},
         {"/example/ws_async", Plug.Cowboy.Handler, {Example.AsyncWSHandler, []}}
       ]
       ++
       Application.get_env(:load, :dispatch, [])
      }
    ]
  end

end
