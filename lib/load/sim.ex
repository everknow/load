defmodule Load.Sim do

  @callback init() :: map()
  @callback run(map()) :: map()
  @callback handle_message(any(), map()) :: map()

  @optional_callbacks handle_message: 2

end
