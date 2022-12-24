import Config

config :load,
  'Example.EchoSim': %{
    "interval_ms" => :timer.seconds(5),
    "stats_interval_ms" => :timer.seconds(1),
    "host" => "localhost",
    "port" => 8888,
    "protocol" => "http"
  },
  sim: Example.EchoSim,
  injected_children: [
    %{id: StatsHistory, start: {GenServer, :start_link, [Example.StatsHistory, %{}, []]}}
  ]

config :logger,
  level: :info
