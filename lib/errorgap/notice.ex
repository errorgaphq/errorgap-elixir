defmodule Errorgap.Notice do
  @moduledoc false

  alias Errorgap.{Backtrace, Breadcrumbs, Configuration, Filter}

  def build(error, opts, %Configuration{} = config) do
    stacktrace = Keyword.get(opts, :stacktrace, [])
    type = error_type(error)
    message = error_message(error)
    causes = collect_causes(error, opts)
    breadcrumbs = Keyword.get(opts, :breadcrumbs) || Breadcrumbs.get()

    default_context = %{
      "notifier" => "errorgap-elixir",
      "notifier_version" => Errorgap.version(),
      "environment" => config.environment,
      "root_directory" => config.root_directory
    }

    context =
      default_context
      |> maybe_put("release", config.release)
      |> maybe_put_list("causes", causes)
      |> maybe_put_list("breadcrumbs", breadcrumbs)
      |> Map.merge(stringify_keys(Keyword.get(opts, :context, %{})))

    %{
      "project_id" => config.project_id,
      "received_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "errors" => [
        %{
          "type" => type,
          "message" => message,
          "backtrace" => Backtrace.from_stacktrace(stacktrace, config.root_directory)
        }
      ],
      "context" => context,
      "environment" => stringify_keys(Keyword.get(opts, :environment, %{})),
      "session" => stringify_keys(Keyword.get(opts, :session, %{})),
      "params" =>
        Filter.params(stringify_keys(Keyword.get(opts, :params, %{})), config.filter_keys)
    }
  end

  defp error_type(%{__exception__: true} = exception), do: exception.__struct__ |> inspect()
  defp error_type(binary) when is_binary(binary), do: "String"
  defp error_type(_other), do: "Error"

  defp error_message(%{__exception__: true} = exception), do: Exception.message(exception)
  defp error_message(binary) when is_binary(binary), do: binary
  defp error_message(other), do: inspect(other)

  # Build `context.causes` from an explicit `:cause` option or by following a
  # `:cause` field on the exception struct, nearest cause first.
  defp collect_causes(error, opts) do
    seed =
      case Keyword.get(opts, :cause) do
        nil -> Map.get(error, :cause)
        cause -> cause
      end

    seed |> chain([], 0) |> Enum.reverse()
  end

  defp chain(nil, acc, _depth), do: acc
  defp chain(_cause, acc, depth) when depth >= 10, do: acc

  defp chain(list, acc, depth) when is_list(list) do
    Enum.reduce(list, acc, fn cause, acc -> chain(cause, acc, depth) end)
  end

  defp chain(cause, acc, depth) do
    entry = %{"type" => error_type(cause), "message" => error_message(cause)}
    next = if is_map(cause), do: Map.get(cause, :cause), else: nil
    chain(next, [entry | acc], depth + 1)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_list(map, _key, []), do: map
  defp maybe_put_list(map, _key, nil), do: map
  defp maybe_put_list(map, key, list) when is_list(list), do: Map.put(map, key, list)
  defp maybe_put_list(map, _key, _), do: map

  defp stringify_keys(%{} = m) do
    Enum.into(m, %{}, fn {k, v} -> {to_string(k), v} end)
  end

  defp stringify_keys(_), do: %{}
end
