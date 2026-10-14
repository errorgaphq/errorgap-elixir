defmodule Errorgap.Filter do
  @moduledoc """
  Masks sensitive map keys before they leave the process.
  """

  @filtered "[FILTERED]"

  @truncated "[TRUNCATED]"
  @max_string 4096
  @max_items 128
  @max_depth 8

  @doc """
  Mask sensitive keys at any depth (inside lists too) and cut long strings
  and large or deeply nested collections.
  """
  @spec params(map() | nil, [String.t()]) :: map()
  def params(nil, _filter_keys), do: %{}
  def params(params, _filter_keys) when params == %{}, do: %{}

  def params(params, filter_keys) when is_map(params) do
    lowered = Enum.map(filter_keys, &String.downcase(to_string(&1)))
    walk_map(params, lowered, 0)
  end

  defp walk_map(map, lowered, depth) do
    map
    |> Enum.take(@max_items)
    |> Enum.into(%{}, fn {k, v} ->
      if sensitive?(k, lowered), do: {k, @filtered}, else: {k, walk(v, lowered, depth + 1)}
    end)
  end

  defp walk(value, lowered, depth) when is_map(value) and not is_struct(value) do
    if depth >= @max_depth, do: @truncated, else: walk_map(value, lowered, depth)
  end

  defp walk(value, lowered, depth) when is_list(value) do
    cond do
      depth >= @max_depth -> @truncated
      Keyword.keyword?(value) and value != [] -> walk_map(Map.new(value), lowered, depth)
      true -> value |> Enum.take(@max_items) |> Enum.map(&walk(&1, lowered, depth + 1))
    end
  end

  defp walk(value, _lowered, _depth) when is_binary(value) do
    if String.valid?(value) and String.length(value) > @max_string,
      do: String.slice(value, 0, @max_string) <> @truncated,
      else: value
  end

  defp walk(value, _lowered, _depth), do: value

  defp sensitive?(key, lowered) do
    lk =
      key
      |> to_string()
      |> String.downcase()

    Enum.any?(lowered, &(&1 != "" and String.contains?(lk, &1)))
  end
end
