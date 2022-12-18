import Config

config :load,
  injected_children: [
    %{id: StatsHistory, start: {GenServer, :start_link, [Example.StatsHistory, %{}, []]}}
  ]

config :logger,
  level: :info
