defmodule Errorgap.Transaction do
  @moduledoc """
  Build APM transactions — a web interaction (`kind: "web"`) or a background
  job (`kind: "job"`) — to deliver via `Errorgap.notify_transaction/2`.
  """

  @doc """
  A web transaction for the normalized route template `path` (e.g.
  `/orders/{id}`) and concrete `path_raw`.

  Options: `:status_code`, `:duration_ms`, `:environment`, `:occurred_at`,
  `:spans`.
  """
  def web(method, path, path_raw, opts \\ []) do
    base("web", opts)
    |> Map.merge(%{"method" => method, "path" => path, "path_raw" => path_raw})
  end

  @doc """
  A background-job transaction for `job_class` on `queue`.

  Options: `:duration_ms`, `:environment`, `:occurred_at`, `:spans`.
  """
  def job(job_class, queue, opts \\ []) do
    base("job", opts)
    |> Map.merge(%{"job_class" => job_class, "queue" => queue})
  end

  defp base(kind, opts) do
    %{
      "kind" => kind,
      "duration_ms" => Keyword.get(opts, :duration_ms, 0),
      "spans" => Keyword.get(opts, :spans, [])
    }
    |> maybe_put("status_code", Keyword.get(opts, :status_code))
    |> maybe_put("environment", Keyword.get(opts, :environment))
    |> maybe_put("occurred_at", Keyword.get(opts, :occurred_at))
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
