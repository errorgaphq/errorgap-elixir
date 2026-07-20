defmodule Errorgap.LogLevel do
  @moduledoc false

  @doc "Canonicalize a level to one of the six the ingestion API recognizes."
  def normalize(level) when is_atom(level), do: normalize(Atom.to_string(level))

  def normalize(level) when is_binary(level) do
    case level |> String.trim() |> String.downcase() do
      l when l in ~w(warning warn) -> "warn"
      l when l in ~w(err severe critical alert emergency) -> "error"
      "notice" -> "info"
      l when l in ~w(trace debug info error fatal) -> l
      _ -> "info"
    end
  end

  def normalize(_), do: "info"

  @doc "Order levels so a minimum-level threshold can be applied client-side."
  def rank("trace"), do: 0
  def rank("debug"), do: 10
  def rank("info"), do: 20
  def rank("warn"), do: 30
  def rank("error"), do: 40
  def rank("fatal"), do: 50
  def rank(_), do: 20
end
