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

    if Configuration.ignored_environment?(config) do
      {:ok, %{status: 202, body: "ignored environment"}}
    else
      case run_hook(Notice.build(error, with_transaction_id(opts), config), config) do
        nil -> {:ok, %{status: 202, body: "dropped by before_notify"}}
        notice -> submit(:notices, notice, config, Keyword.get(opts, :sync, false))
      end
    end
  rescue
    exc -> {:error, exc}
  end

  # `config :errorgap, before_notify: fun | {Module, :function}` sees each
  # notice and returns it (changed or not), or false/nil to drop it. A hook
  # that raises is skipped: a bug in a filter must not lose the error it was
  # filtering.
  defp run_hook(notice, %Configuration{before_notify: nil}), do: notice

  defp run_hook(notice, %Configuration{before_notify: hook}) do
    result =
      case hook do
        {module, function} -> apply(module, function, [notice])
        fun when is_function(fun, 1) -> fun.(notice)
        _ -> notice
      end

    case result do
      false -> nil
      nil -> nil
      %{"errors" => _} = changed -> changed
      _ -> notice
    end
  rescue
    _ -> notice
  catch
    _, _ -> notice
  end

  # The request or job this error was raised in (Errorgap.Transaction.run/2),
  # unless the caller set one, so errorgap links the two.
  defp with_transaction_id(opts) do
    case Errorgap.Transaction.current_id() do
      nil ->
        opts

      id ->
        Keyword.update(opts, :context, %{"transaction_id" => id}, fn context ->
          if Map.has_key?(context, :transaction_id) or Map.has_key?(context, "transaction_id"),
            do: context,
            else: Map.put(context, "transaction_id", id)
        end)
    end
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

  @max_attempts 3
  @retry_delay 30_000
  @backlog_size 100

  @impl true
  def handle_cast({:deliver, resource, payload}, state) do
    {:noreply, deliver_from_queue(resource, payload, 1, state)}
  end

  @impl true
  def handle_info({:retry, resource, payload, attempt}, state) do
    state = Map.update(state, :backlog, 0, &max(&1 - 1, 0))
    {:noreply, deliver_from_queue(resource, payload, attempt, state)}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp deliver_from_queue(resource, payload, attempt, state) do
    result = deliver(resource, payload, Configuration.build())
    backlog = Map.get(state, :backlog, 0)

    if retryable?(result) and attempt < @max_attempts and backlog < @backlog_size do
      Process.send_after(self(), {:retry, resource, payload, attempt + 1}, @retry_delay * attempt)
      Map.put(state, :backlog, backlog + 1)
    else
      state
    end
  rescue
    _ -> state
  end

  @doc """
  Network failures and 5xx responses are worth another try. A 4xx is not:
  the server understood and refused, and after a 429 the payload is dropped
  so a limited project is not sent the same burst again.
  """
  def retryable?({:error, :rate_limited}), do: false
  def retryable?({:error, _reason}), do: true
  def retryable?({:ok, %{status: status}}) when is_integer(status), do: status >= 500
  def retryable?(_), do: false

  @pause_key {__MODULE__, :paused_until}

  @doc "True while delivery is paused at the server's request (a 429 or 503 with Retry-After)."
  def paused? do
    # Monotonic time can be negative, so "not paused" is nil, not 0.
    case :persistent_term.get(@pause_key, nil) do
      nil -> false
      until -> System.monotonic_time(:millisecond) < until
    end
  end

  @doc false
  def resume, do: :persistent_term.put(@pause_key, nil)

  defp pause_for(headers) do
    seconds =
      headers
      |> Enum.find_value(fn {name, value} ->
        if String.downcase(to_string(name)) == "retry-after", do: to_string(value)
      end)
      |> case do
        nil -> 60
        text ->
          case Integer.parse(String.trim(text)) do
            {n, _} -> n
            :error -> 60
          end
      end
      |> max(1)
      |> min(300)

    :persistent_term.put(@pause_key, System.monotonic_time(:millisecond) + seconds * 1000)
  end

  @impl true
  def handle_call(:flush, _from, state), do: {:reply, :ok, state}

  # -- Delivery --

  defp queue_length do
    case Process.whereis(@name) do
      nil -> 0
      pid -> pid |> Process.info(:message_queue_len) |> elem(1)
    end
  rescue
    _ -> 0
  end

  defp submit(resource, payload, config, sync?) do
    cond do
      Configuration.ignored_environment?(config) ->
        {:ok, %{status: 204}}

      sync? ->
        deliver(resource, payload, config)

      config.async ->
        # A burst must not grow the worker's mailbox without limit.
        if queue_length() >= config.queue_size do
          {:error, :queue_full}
        else
          GenServer.cast(@name, {:deliver, resource, payload})
          :ok
        end

      true ->
        deliver(resource, payload, config)
    end
  end

  defp deliver(resource, payload, %Configuration{} = config) do
    if paused?(), do: {:error, :rate_limited}, else: post(resource, payload, config)
  end

  defp post(resource, payload, %Configuration{} = config) do
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
      {:ok, {{_proto, status, _reason}, response_headers, response_body}} ->
        if status in [429, 503], do: pause_for(response_headers)
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
