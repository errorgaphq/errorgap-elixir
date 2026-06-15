defmodule Errorgap.Backtrace do
  @moduledoc false

  @doc """
  Convert an Elixir/Erlang stacktrace into the Errorgap backtrace format.
  """
  def from_stacktrace(stacktrace, root_directory) when is_list(stacktrace) do
    stacktrace
    |> Enum.with_index()
    |> Enum.map(fn {entry, index} ->
      {file, line, function} = decode(entry)

      %{
        "file" => relative(file, root_directory),
        "line" => line,
        "function" => function,
        "in_app" => in_app?(file, root_directory),
        "index" => index
      }
    end)
  end

  def from_stacktrace(_, _), do: []

  defp decode({module, fun, arity_or_args, location}) do
    arity = if is_list(arity_or_args), do: length(arity_or_args), else: arity_or_args
    file = location |> Keyword.get(:file) |> to_string_or_nil()
    line = Keyword.get(location, :line)
    function = "#{inspect(module)}.#{fun}/#{arity}"
    {file, line, function}
  end

  defp decode(_), do: {nil, nil, nil}

  defp to_string_or_nil(nil), do: nil
  defp to_string_or_nil(charlist) when is_list(charlist), do: to_string(charlist)
  defp to_string_or_nil(binary) when is_binary(binary), do: binary

  defp relative(nil, _root), do: nil

  defp relative(file, root) when is_binary(root) and root != "" do
    normalized = if String.ends_with?(root, "/"), do: root, else: root <> "/"
    if String.starts_with?(file, normalized), do: String.replace_prefix(file, normalized, ""), else: file
  end

  defp relative(file, _root), do: file

  defp in_app?(nil, _root), do: false

  defp in_app?(file, root) when is_binary(root) and root != "" do
    String.starts_with?(file, root) and not String.contains?(file, "/deps/")
  end

  defp in_app?(_, _), do: false
end
