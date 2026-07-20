defmodule Errorgap.Backtrace do
  @moduledoc false

  @source_context_lines 6
  @max_source_line_length 400
  @max_source_file_bytes 2_000_000

  @doc """
  Convert an Elixir/Erlang stacktrace into the Errorgap backtrace format,
  attaching a source excerpt for each frame whose file is readable.

  Frames without a file (Erlang BIFs such as `:erlang.div`) are dropped: the
  ingestion contract requires a `file` on every frame.
  """
  def from_stacktrace(stacktrace, root_directory) when is_list(stacktrace) do
    stacktrace
    |> Enum.map(&build_frame(&1, root_directory))
    |> Enum.reject(&is_nil/1)
    |> Enum.with_index()
    |> Enum.map(fn {frame, index} -> Map.put(frame, "index", index) end)
  end

  def from_stacktrace(_, _), do: []

  defp build_frame({module, fun, arity_or_args, location}, root) do
    arity = if is_list(arity_or_args), do: length(arity_or_args), else: arity_or_args
    rel_file = location |> Keyword.get(:file) |> to_string_or_nil()
    abs_file = compile_source(module)
    best_file = abs_file || rel_file

    case display(best_file, root) do
      nil ->
        nil

      display_file ->
        line = Keyword.get(location, :line)
        column = Keyword.get(location, :column)

        %{
          "file" => display_file,
          "line" => line,
          "function" => "#{inspect(module)}.#{fun}/#{arity}",
          "in_app" => in_app?(best_file)
        }
        |> maybe_put("column", column)
        |> maybe_put_source(source_file(abs_file, rel_file, root), line)
    end
  end

  defp build_frame(_, _), do: nil

  # A module's absolute source path, recorded at compile time. Available for
  # loaded modules (including dependencies), so dependency frames classify and
  # resolve source correctly even though the stacktrace file is relative to the
  # dependency's own root.
  defp compile_source(module) when is_atom(module) do
    case module.module_info(:compile)[:source] do
      source when is_list(source) -> to_string(source)
      source when is_binary(source) -> source
      _ -> nil
    end
  rescue
    _ -> nil
  catch
    _, _ -> nil
  end

  defp compile_source(_), do: nil

  defp to_string_or_nil(nil), do: nil
  defp to_string_or_nil(charlist) when is_list(charlist), do: to_string(charlist)
  defp to_string_or_nil(binary) when is_binary(binary), do: binary

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_source(map, _file, nil), do: map

  defp maybe_put_source(map, file, line) do
    case source_excerpt(file, line) do
      nil -> map
      source -> Map.put(map, "source", source)
    end
  end

  # Friendly path: relative to the project root when the file lives under it,
  # else stripped to the dependency segment.
  defp display(nil, _root), do: nil

  defp display(file, root) when is_binary(root) and root != "" do
    normalized = if String.ends_with?(root, "/"), do: root, else: root <> "/"

    if String.starts_with?(file, normalized),
      do: String.replace_prefix(file, normalized, ""),
      else: strip_deps(file)
  end

  defp display(file, _root), do: strip_deps(file)

  defp strip_deps(file) do
    case String.split(file, "/deps/", parts: 2) do
      [_, rest] -> "deps/" <> rest
      _ -> file
    end
  end

  # Application frames are Elixir source files under the project that aren't
  # dependencies or the standard library.
  defp in_app?(nil), do: false

  defp in_app?(file) do
    cond do
      String.contains?(file, "/deps/") or String.starts_with?(file, "deps/") -> false
      String.contains?(file, "/elixir/lib/") or String.contains?(file, "/lib/elixir/") -> false
      String.contains?(file, "/otp/") or String.ends_with?(file, ".erl") -> false
      String.ends_with?(file, ".ex") or String.ends_with?(file, ".exs") -> true
      true -> false
    end
  end

  # Absolute, readable path to load source from.
  defp source_file(abs_file, rel_file, root) do
    cond do
      is_binary(abs_file) and File.regular?(abs_file) ->
        abs_file

      is_binary(rel_file) and File.regular?(rel_file) ->
        rel_file

      is_binary(rel_file) and is_binary(root) and root != "" and
          File.regular?(Path.join(root, rel_file)) ->
        Path.join(root, rel_file)

      true ->
        nil
    end
  end

  defp source_excerpt(file, line) when is_binary(file) and is_integer(line) and line > 0 do
    with {:ok, %File.Stat{size: size}} when size <= @max_source_file_bytes <- File.stat(file),
         {:ok, contents} <- File.read(file) do
      lines = String.split(contents, ~r/\r?\n/)
      total = length(lines)

      if line > total do
        nil
      else
        start_line = max(1, line - @source_context_lines)
        end_line = min(total, line + @source_context_lines)

        excerpt =
          lines
          |> Enum.slice((start_line - 1)..(end_line - 1))
          |> Enum.map(&String.slice(&1, 0, @max_source_line_length))

        %{"start_line" => start_line, "lines" => excerpt}
      end
    else
      _ -> nil
    end
  end

  defp source_excerpt(_, _), do: nil
end
