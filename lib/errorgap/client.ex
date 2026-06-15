defmodule Errorgap.Client do
  @moduledoc false

  use GenServer

  alias Errorgap.{Configuration, Notice}

  @name __MODULE__

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: @name)

  @doc """
  Send a notice. In async mode the notice is cast to the worker and `:ok`
  returned immediately. In sync mode the HTTP call is awaited.
  """
  def notify(error, opts) do
    config = config()
    notice = Notice.build(error, opts, config)

    cond do
      Keyword.get(opts, :sync, false) -> deliver(notice, config)
      config.async -> GenServer.cast(@name, {:notify, notice}); :ok
      true -> deliver(notice, config)
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
  def handle_cast({:notify, notice}, state) do
    config = Configuration.build()
    deliver(notice, config)
    {:noreply, state}
  end

  @impl true
  def handle_call(:flush, _from, state), do: {:reply, :ok, state}

  # -- Delivery --

  defp deliver(notice, %Configuration{} = config) do
    url = "#{trim_trailing_slash(config.endpoint)}/api/projects/#{config.project_slug}/notices"
    body = Errorgap.JSON.encode(notice)

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

  defp trim_trailing_slash(s) do
    if String.ends_with?(s, "/"), do: String.trim_trailing(s, "/"), else: s
  end
end
