defmodule Errorgap do
  @moduledoc """
  Elixir notifier for Errorgap. Configure via `Application` env, then call
  `Errorgap.notify/2` directly, attach `Errorgap.Plug` to your Phoenix
  endpoint, or wire `Errorgap.LoggerHandler` into `:logger` for handler-style
  capture of crash reports and high-severity logs.
  """

  @version "0.1.0"

  def version, do: @version

  @doc """
  Report an exception or string error to Errorgap. Returns `:ok` when the
  notice is queued or successfully delivered, `{:error, reason}` otherwise.
  """
  @spec notify(Exception.t() | binary(), keyword()) :: :ok | {:error, term()}
  def notify(error, opts \\ []) do
    Errorgap.Client.notify(error, opts)
  end

  @doc """
  Block until all queued notices have been delivered. Use during graceful
  shutdown.
  """
  @spec flush(timeout()) :: :ok
  def flush(timeout \\ 5_000), do: Errorgap.Client.flush(timeout)
end
