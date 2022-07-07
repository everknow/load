defmodule Load.MixProject do
  use Mix.Project

  def project do
    vsn =
      case File.read("vsn.txt") do
        {:ok, v} -> String.trim(v)
        _ -> "0.0.0"
      end
    [
      app: :load,
      version: vsn,
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Load.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:gun, "~> 2.0.0-rc.2"},
      {:jason, "~> 1.3"},
      {:plug_cowboy, "~> 2.5"},
      {:corsica, "~> 1.1"}
    ]
  end
end
