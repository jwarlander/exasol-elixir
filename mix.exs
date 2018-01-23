defmodule CirroConnect.Mixfile do
  use Mix.Project

  def project do
    [
      app: :cirro_connect,
      version: "0.1.0",
      elixir: "~> 1.4",
      start_permanent: Mix.env == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:websockex, "~> 0.4.0"},
      {:poison, ">= 1.5.0"}
    ]
  end
end
