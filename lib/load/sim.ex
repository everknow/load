defmodule Load.Sim do

  @callback init() :: map()
  @callback run(map()) :: map()
  @callback handle_message(any(), map()) :: map()

  @optional_callbacks handle_message: 2


    # %{
  #   'Example.EchoSim': %{
  #     "worker_interval" => 2
  #   }
  # }
  def config_time(config, sim) do
    if config[sim] do
      config
      |> Map.put(:interval_ms, apply(:timer,
        config[sim]["worker_timeunit"] || "seconds" |> String.to_existing_atom(),
        config[sim]["worker_interval"] || 1))
      |> Map.put(:interval_ms, apply(:timer,
        config[sim]["worker_stats_timeunit"] || "seconds" |> String.to_existing_atom(),
        config[sim]["worker_stats_interval"] || 5))
    else
      config
    end
  end

end
