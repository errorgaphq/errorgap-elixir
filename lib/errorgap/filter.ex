defmodule Errorgap.Filter do
  @moduledoc """
  Masks sensitive map keys before they leave the process.
  """

  @filtered "[FILTERED]"

  @spec params(map(), [String.t()]) :: map()
  def params(nil, _filter_keys), do: %{}
  def params(params, _filter_keys) when params == %{}, do: %{}

  def params(params, filter_keys) when is_map(params) do
    lowered = Enum.map(filter_keys, &String.downcase/1)
    walk(params, lowered)
  end

  defp walk(map, lowered) do
    Enum.into(map, %{}, fn {k, v} ->
      cond do
        sensitive?(k, lowered) -> {k, @filtered}
        is_map(v) and not is_struct(v) -> {k, walk(v, lowered)}
        true -> {k, v}
      end
    end)
  end

  defp sensitive?(key, lowered) do
    lk =
      key
      |> to_string()
      |> String.downcase()

    Enum.any?(lowered, &String.contains?(lk, &1))
  end
end
