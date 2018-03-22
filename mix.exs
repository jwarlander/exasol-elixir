defmodule CirroConnect.Mixfile do
  use Mix.Project

  @project_url "https://github.com/cirroinc/cirro_connect"

  def project do
    [
      app: :cirro_connect,
      version: "0.1.3",
      elixir: "~> 1.4",
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      name: "CirroConnect",
      source_url: @project_url,
      homepage_url: "https://www.cirro.com"
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
    "An Elixir websocket-based SQL connector for Cirro. CirroConnect allows Elixir programs to connect to Cirro (http://www.cirro.com) using its websocket API and issue federated queries."
  end

  defp package() do
    [
      files: ["lib", "test", "mix.exs", "README*", "LICENSE*"],
      maintainers: ["Gerrard Hocks", "Daniel Parnell"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @project_url
      }
    ]
  end
end
