defmodule Exasol.Mixfile do
  use Mix.Project

  @project_url "https://github.com/jwarlander/exasol-elixir"

  def project do
    [
      app: :exasol,
      version: "0.1.0",
      elixir: "~> 1.4",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      name: "Exasol"
    ]
  end

  def application do
    []
  end

  defp deps do
    [
      {:websockex, "~> 0.4.0"},
      {:poison, ">= 1.5.0"},
      {:ex_doc, ">= 0.0.0", only: :dev}
    ]
  end

  defp description() do
    "Exasol driver for Elixir"
  end

  defp package() do
    [
      files: ["lib", "test", "mix.exs", "README*", "LICENSE*"],
      maintainers: ["Johan Wärlander"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @project_url
      }
    ]
  end
end
