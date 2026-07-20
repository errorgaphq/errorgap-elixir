defmodule Errorgap.Client do
  @moduledoc false

  use GenServer

  alias Errorgap.{Configuration, LogLevel, Notice}

  @name __MODULE__

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: @name)

  @doc """
  Send a notice. In async mode the notice is cast to the worker and `:ok`
  returned immediately. In sync mode the HTTP call is awaited.
  """
  def notify(error, opts) do
    config = config()
    notice = Notice.build(error, opts, config)
    submit(:notices, notice, config, Keyword.get(opts, :sync, false))
  rescue
    exc -> {:error, exc}
  end

  @doc "Deliver an APM transaction (a web interaction or a background job)."
  def notify_transaction(transaction, opts \\ []) when is_map(transaction) do
    config = config()

    if config.apm_enabled and sample?(config.apm_sample_rate) do
      payload =
        transaction
        |> Map.put_new("environment", config.environment)
        |> Map.put_new("occurred_at", now())

      submit(:transactions, payload, config, Keyword.get(opts, :sync, false))
    else
      {:ok, %{status: 204}}
    end
  rescue
    exc -> {:error, exc}
  end

  @doc "Deliver a structured log line."
  def notify_log(message, level \\ "info", source \\ nil, opts \\ []) do
    config = config()
    normalized = LogLevel.normalize(level)

    if config.logs_enabled and
         LogLevel.rank(normalized) >= LogLevel.rank(LogLevel.normalize(config.minimum_log_level)) do
      payload =
        %{
          "message" => to_string(message),
          "level" => normalized,
          "environment" => config.environment,
          "occurred_at" => now()
        }
        |> maybe_put("source", source)

      submit(:logs, payload, config, Keyword.get(opts, :sync, false))
    else
      {:ok, %{status: 204}}
    end
  rescue
    exc -> {:error, exc}
  end

  @doc "Block until the worker's mailbox is empty."
  def flush(timeout \\ 5_000) do
    GenServer.call(@name, :flush, timeout)
  catch
    :exit, _ -> :ok
  end

  def config do
    Configuration.build() |> Configuration.validate!()
  end

  # -- GenServer callbacks --

  @impl true
  def init(_), do: {:ok, %{}}

  @impl true
  def handle_cast({:deliver, resource, payload}, state) do
    config = Configuration.build()
    deliver(resource, payload, config)
    {:noreply, state}
  end

  @impl true
  def handle_call(:flush, _from, state), do: {:reply, :ok, state}

  # -- Delivery --

  defp submit(resource, payload, config, sync?) do
    cond do
      sync? ->
        deliver(resource, payload, config)

      config.async ->
        GenServer.cast(@name, {:deliver, resource, payload})
        :ok

      true ->
        deliver(resource, payload, config)
    end
  end

  defp deliver(resource, payload, %Configuration{} = config) do
    url =
      "#{trim_trailing_slash(config.endpoint)}/api/projects/#{config.project_slug}/#{resource}"

    body = Errorgap.JSON.encode(payload)

    headers = [
      {~c"content-type", ~c"application/json"},
      {~c"user-agent", String.to_charlist("errorgap-elixir/#{Errorgap.version()}")}
    ]

    headers =
      if config.api_key not in [nil, ""] do
        [{~c"x-errorgap-project-key", String.to_charlist(config.api_key)} | headers]
      else
        headers
      end

    request = {String.to_charlist(url), headers, ~c"application/json", body}
    http_opts = [timeout: config.timeout, connect_timeout: config.timeout]
    opts = [body_format: :binary]

    case :httpc.request(:post, request, http_opts, opts) do
      {:ok, {{_proto, status, _reason}, _hdrs, response_body}} ->
        {:ok, %{status: status, body: response_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp sample?(rate) when is_number(rate) do
    cond do
      rate >= 1.0 -> true
      rate <= 0.0 -> false
      true -> :rand.uniform() < rate
    end
  end

  defp sample?(_), do: true

  defp now, do: DateTime.utc_now() |> DateTime.to_iso8601()

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp trim_trailing_slash(s) do
    if String.ends_with?(s, "/"), do: String.trim_trailing(s, "/"), else: s
  end
end
