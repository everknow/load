defmodule Load.Sim do
  @callback init() :: map()
  @callback run(map()) :: map()
end
