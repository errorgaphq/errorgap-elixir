defmodule Errorgap do
  @moduledoc """
  Elixir notifier for Errorgap. Configure via `Application` env, then call
  `Errorgap.notify/2` directly, attach `Errorgap.Plug` to your Phoenix
  endpoint, or wire `Errorgap.LoggerHandler` into `:logger` for handler-style
  capture of crash reports and high-severity logs.

  Beyond exceptions, the SDK ships source-aware backtraces, nested causes,
  breadcrumbs (`add_breadcrumb/3`), structured logs (`log/3`), and APM
  transactions (`notify_transaction/2`).
  """

  @version "0.2.0"

  def version, do: @version

  @doc """
  Report an exception or string error to Errorgap. Returns `:ok` when the
  notice is queued or successfully delivered, `{:error, reason}` otherwise.

  Options include `:stacktrace`, `:context`, `:environment`, `:session`,
  `:params`, `:cause` (an exception whose `:cause` chain is flattened into
  `context.causes`), `:breadcrumbs`, and `:sync`.
  """
  @spec notify(Exception.t() | binary(), keyword()) :: :ok | {:error, term()} | {:ok, map()}
  def notify(error, opts \\ []) do
    Errorgap.Client.notify(error, opts)
  end

  @doc "Deliver a structured log line at the given level with an optional source."
  @spec log(binary(), binary() | atom(), binary() | nil, keyword()) ::
          :ok | {:error, term()} | {:ok, map()}
  def log(message, level \\ "info", source \\ nil, opts \\ []) do
    Errorgap.Client.notify_log(message, level, source, opts)
  end

  @doc """
  Deliver an APM transaction. Build one with `Errorgap.Transaction.web/4` or
  `Errorgap.Transaction.job/3`.
  """
  @spec notify_transaction(map(), keyword()) :: :ok | {:error, term()} | {:ok, map()}
  def notify_transaction(transaction, opts \\ []) do
    Errorgap.Client.notify_transaction(transaction, opts)
  end

  @doc """
  Record a diagnostic breadcrumb attached to subsequent notices built in this
  process as `context.breadcrumbs`.
  """
  @spec add_breadcrumb(binary(), binary() | atom() | nil, map()) :: :ok
  def add_breadcrumb(message, category \\ nil, metadata \\ %{}) do
    max = Errorgap.Client.config().max_breadcrumbs
    Errorgap.Breadcrumbs.add(message, category, metadata, max)
  rescue
    _ -> Errorgap.Breadcrumbs.add(message, category, metadata)
  end

  @doc "Clear the current process's breadcrumbs."
  @spec clear_breadcrumbs() :: :ok
  def clear_breadcrumbs, do: Errorgap.Breadcrumbs.clear()

  @doc """
  Block until all queued notices have been delivered. Use during graceful
  shutdown.
  """
  @spec flush(timeout()) :: :ok
  def flush(timeout \\ 5_000), do: Errorgap.Client.flush(timeout)
end
