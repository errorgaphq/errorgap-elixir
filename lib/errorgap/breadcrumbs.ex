defmodule Errorgap.Breadcrumbs do
  @moduledoc """
  Per-process breadcrumb trail attached to notices as `context.breadcrumbs`.

  Breadcrumbs are stored in the process dictionary, so they accumulate within
  the process handling a request or job and are captured when that process
  builds a notice.
  """

  @key :errorgap_breadcrumbs

  @doc """
  Record a breadcrumb. `metadata` is an arbitrary map. Older breadcrumbs beyond
  `max` are dropped.
  """
  def add(message, category \\ nil, metadata \\ %{}, max \\ 25) do
    if max <= 0 do
      :ok
    else
      crumb =
        %{
          "message" => to_string(message),
          "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
        }
        |> maybe_put("category", category)
        |> maybe_put_map("metadata", metadata)

      crumbs = (get() ++ [crumb]) |> Enum.take(-max)
      Process.put(@key, crumbs)
      :ok
    end
  end

  @doc "Return the current process's breadcrumbs."
  def get do
    Process.get(@key, [])
  end

  @doc "Clear the current process's breadcrumbs."
  def clear do
    Process.delete(@key)
    :ok
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, to_string(value))

  defp maybe_put_map(map, _key, meta) when meta == %{}, do: map
  defp maybe_put_map(map, key, meta) when is_map(meta), do: Map.put(map, key, stringify(meta))
  defp maybe_put_map(map, _key, _meta), do: map

  defp stringify(%{} = m), do: Enum.into(m, %{}, fn {k, v} -> {to_string(k), v} end)
end
