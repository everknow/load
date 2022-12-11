import Config

config :load,
  sim: Example.EchoSim,
  injected_children: [
    %{id: StatsHistory, start: {GenServer, :start_link, [Example.StatsHistory, %{}, []]}}
  ]

config :logger,
  level: :info
