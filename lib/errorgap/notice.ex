defmodule Errorgap.Notice do
  @moduledoc false

  alias Errorgap.{Backtrace, Configuration, Filter}

  def build(error, opts, %Configuration{} = config) do
    stacktrace = Keyword.get(opts, :stacktrace, [])
    type = error_type(error)
    message = error_message(error)

    default_context = %{
      "notifier" => "errorgap-elixir",
      "notifier_version" => Errorgap.version(),
      "environment" => config.environment,
      "root_directory" => config.root_directory
    }

    context =
      default_context
      |> maybe_put("release", config.release)
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
      "params" => Filter.params(stringify_keys(Keyword.get(opts, :params, %{})), config.filter_keys)
    }
  end

  defp error_type(%{__exception__: true} = exception), do: exception.__struct__ |> inspect()
  defp error_type(binary) when is_binary(binary), do: "String"
  defp error_type(_other), do: "Error"

  defp error_message(%{__exception__: true} = exception), do: Exception.message(exception)
  defp error_message(binary) when is_binary(binary), do: binary
  defp error_message(other), do: inspect(other)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp stringify_keys(%{} = m) do
    Enum.into(m, %{}, fn {k, v} -> {to_string(k), v} end)
  end

  defp stringify_keys(_), do: %{}
end
