defmodule Load.Application do
  use Application

  @impl true
  @spec start(any, any) :: {:error, any} | {:ok, pid}
  def start(_type, _args) do
    children = [
      Plug.Cowboy.child_spec(
        scheme: :http,
        plug: Load.Router,
        options: [
          port: Application.get_env(:load, :ws_port, 8888),
          dispatch: dispatch()
        ]
      ),
      # , extra_arguments: [[a: :b]]}
      {DynamicSupervisor, strategy: :one_for_one, name: Load.Worker.Supervisor},
      {DynamicSupervisor, strategy: :one_for_one, name: Load.Connection.Supervisor},
      %{id: :pg, start: {:pg, :start_link, []}},
      %{id: LocalStats, start: {GenServer, :start_link, [Stats, %{group: Local}, []]}},
      %{
        id: GlobalStats,
        start: {GenServer, :start_link, [Stats, %{group: Global, history: []}, []]}
      }
    ]

    opts = [strategy: :one_for_one, name: Load.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def dispatch do
    [
      {:_,
       [
         {"/ws", Load.WSHandler, []},
         {"/example/echo", Plug.Cowboy.Handler, {Example.EchoRouter, []}}
         #  {:_, Plug.Cowboy.Handler, {Example.EchoRouter, []}}
       ]}
    ]
  end
end
