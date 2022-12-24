defmodule Example.NodeConfigurator do
  def configure(config) do
    config
    |> Map.to_list()
    # |> Enum.map(fn {k,v}-> {String.to_existing_atom(k), v} end)
    |> Application.put_all_env()
  end
end
