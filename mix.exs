defmodule Errorgap.MixProject do
  use Mix.Project

  @version "0.2.0"
  @source_url "https://github.com/errorgaphq/errorgap-elixir"

  def project do
    [
      app: :errorgap,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Elixir notifier for Errorgap error tracking.",
      package: package(),
      source_url: @source_url
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger, :inets, :ssl],
      mod: {Errorgap.Application, []}
    ]
  end

  defp deps do
    [
      {:plug, "~> 1.15", optional: true},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end
end
