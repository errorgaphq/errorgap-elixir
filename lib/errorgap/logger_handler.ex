defmodule Errorgap.LoggerHandler do
  @moduledoc """
  An OTP `:logger` handler that reports crash reports to Errorgap.

  Attach it once at startup — for example in your application's `start/2` — so
  unhandled exceptions in supervised processes (GenServers, Tasks, Phoenix
  channels) are captured automatically:

      Errorgap.LoggerHandler.attach()

  Only log events carrying a `:crash_reason` are reported; ordinary log lines
  are ignored. Deliver those explicitly with `Errorgap.log/3`.
  """

  @handler_id :errorgap

  @doc "Attach the handler to the default logger. Idempotent."
  def attach(opts \\ []) do
    config = %{level: Keyword.get(opts, :level, :error)}

    case :logger.add_handler(@handler_id, __MODULE__, %{config: config}) do
      :ok -> :ok
      {:error, {:already_exist, _}} -> :ok
      other -> other
    end
  end

  @doc "Detach the handler."
  def detach do
    _ = :logger.remove_handler(@handler_id)
    :ok
  end

  @doc false
  # :logger handler callback.
  def log(%{meta: %{crash_reason: {reason, stacktrace}}}, _config)
      when is_list(stacktrace) do
    error = normalize(reason)
    Errorgap.notify(error, stacktrace: stacktrace, context: %{"source" => "logger_handler"})
    :ok
  rescue
    _ -> :ok
  end

  def log(_event, _config), do: :ok

  defp normalize(%{__exception__: true} = exception), do: exception
  defp normalize(reason), do: %RuntimeError{message: format_reason(reason)}

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)
end
