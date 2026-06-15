defmodule Errorgap.JSON do
  @moduledoc """
  Minimal JSON encoder. Avoids a runtime dependency on `:jason` so the
  library has zero non-stdlib deps. Handles only the types used in notice
  envelopes: map, list, binary, atom, number, boolean, nil.
  """

  def encode(value), do: do_encode(value) |> IO.iodata_to_binary()

  defp do_encode(nil), do: "null"
  defp do_encode(true), do: "true"
  defp do_encode(false), do: "false"
  defp do_encode(value) when is_atom(value), do: encode_string(Atom.to_string(value))
  defp do_encode(value) when is_binary(value), do: encode_string(value)
  defp do_encode(value) when is_integer(value), do: Integer.to_string(value)
  defp do_encode(value) when is_float(value), do: Float.to_string(value)

  defp do_encode(list) when is_list(list) do
    inner =
      list
      |> Enum.map(&do_encode/1)
      |> Enum.intersperse(",")

    [?[, inner, ?]]
  end

  defp do_encode(%{} = map) do
    inner =
      map
      |> Enum.map(fn {k, v} -> [encode_string(to_string(k)), ?:, do_encode(v)] end)
      |> Enum.intersperse(",")

    [?{, inner, ?}]
  end

  defp do_encode(other), do: encode_string(inspect(other))

  defp encode_string(value) when is_binary(value) do
    [?", escape(value, []), ?"]
  end

  defp escape(<<>>, acc), do: Enum.reverse(acc)
  defp escape(<<?\\, rest::binary>>, acc), do: escape(rest, ["\\\\" | acc])
  defp escape(<<?", rest::binary>>, acc), do: escape(rest, ["\\\"" | acc])
  defp escape(<<?\n, rest::binary>>, acc), do: escape(rest, ["\\n" | acc])
  defp escape(<<?\r, rest::binary>>, acc), do: escape(rest, ["\\r" | acc])
  defp escape(<<?\t, rest::binary>>, acc), do: escape(rest, ["\\t" | acc])
  defp escape(<<?\b, rest::binary>>, acc), do: escape(rest, ["\\b" | acc])
  defp escape(<<?\f, rest::binary>>, acc), do: escape(rest, ["\\f" | acc])

  defp escape(<<c, rest::binary>>, acc) when c < 0x20 do
    escape(rest, [:io_lib.format("\\u~4..0x", [c]) | acc])
  end

  defp escape(<<c, rest::binary>>, acc), do: escape(rest, [<<c>> | acc])
end
