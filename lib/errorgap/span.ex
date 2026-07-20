defmodule Errorgap.Span do
  @moduledoc """
  Build APM spans (database queries and outbound HTTP calls) to attach to a
  transaction via `Errorgap.notify_transaction/2`.
  """

  @doc """
  A database query span. The SQL is normalized so query shapes aggregate.

  Options: `:file`, `:line`, `:function`.
  """
  def database(sql, duration_ms, opts \\ []) when is_binary(sql) do
    build("db", duration_ms, opts) |> Map.put("sql", normalize_sql(sql))
  end

  @doc "An outbound HTTP / external service span. Options: `:file`, `:line`, `:function`."
  def external(duration_ms, opts \\ []) do
    build("http", duration_ms, opts)
  end

  defp build(kind, duration_ms, opts) do
    %{"kind" => kind, "duration_ms" => duration_ms}
    |> maybe_put("file", Keyword.get(opts, :file))
    |> maybe_put("line", Keyword.get(opts, :line))
    |> maybe_put("fn_name", Keyword.get(opts, :function))
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  @doc "Strip literals so query shapes aggregate: `'…'` and numbers become `?`."
  def normalize_sql(sql) do
    sql
    |> String.replace(~r/'(?:''|[^'])*'/, "?")
    |> String.replace(~r/\b\d+(?:\.\d+)?\b/, "?")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end
end
