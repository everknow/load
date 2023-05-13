defmodule Load.MixProject do
  use Mix.Project

  def project do
    [
      app: :load,
      version: "0.3.0",
      elixir: "~> 1.10",
      # build_embedded: Mix.env == :prod,
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      deps: deps(),
      name: "load",
      source_url: "https://github.com/everknow/load"
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
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:gun, "~> 2.0.1"},
      {:jason, "~> 1.4"},
      {:cowboy, "~> 2.10.0"}
    ]
  end

  defp description() do
    "A simple library for load testing"
  end

  defp package() do
    [
      files: ~w(lib .formatter.exs mix.exs config test .gitignore README.md LICENSE),
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/everknow/load"}
    ]
  end
end
