defmodule Errorgap.Transaction do
  @key {:errorgap, :transaction_id}

  @moduledoc """
  Build APM transactions — a web interaction (`kind: "web"`) or a background
  job (`kind: "job"`) — to deliver via `Errorgap.notify_transaction/2`.
  """

  @doc """
  A web transaction for the normalized route template `path` (e.g.
  `/orders/{id}`) and concrete `path_raw`.

  Options: `:status_code`, `:duration_ms`, `:environment`, `:occurred_at`,
  `:spans`, `:id` (generated when absent), and `:trace_id` — the
  `x-errorgap-trace` header a browser SDK sent with the request, which links
  the browser's view of the call to this transaction (ignored unless it is a
  well-formed UUID; see `browser_trace_id/1`).
  """
  def web(method, path, path_raw, opts \\ []) do
    base("web", opts)
    |> Map.merge(%{"method" => method, "path" => path, "path_raw" => path_raw})
    |> maybe_put("trace_id", browser_trace_id(Keyword.get(opts, :trace_id)))
  end

  @doc "The header the errorgap browser SDK sends with API calls."
  def trace_header, do: "x-errorgap-trace"

  @doc """
  The trace id in an `x-errorgap-trace` header value, lowercased, or `nil`
  unless it is a well-formed UUID. In a Plug pipeline:

      Plug.Conn.get_req_header(conn, "x-errorgap-trace") |> List.first()
  """
  def browser_trace_id(header) when is_binary(header) do
    value = header |> String.trim() |> String.downcase()

    if Regex.match?(~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/, value),
      do: value
  end

  def browser_trace_id(_), do: nil

  @doc """
  A background-job transaction for `job_class` on `queue`.

  Options: `:duration_ms`, `:environment`, `:occurred_at`, `:spans`.
  """
  def job(job_class, queue, opts \\ []) do
    base("job", opts)
    |> Map.merge(%{"job_class" => job_class, "queue" => queue})
  end

  @doc """
  Run `fun` as part of `transaction` (or a transaction id): errors reported
  from this process while it runs carry the id as `context.transaction_id`,
  so errorgap links them to the request or job. The previous id is restored
  afterwards.
  """
  def run(transaction_or_id, fun) when is_function(fun, 0) do
    previous = Process.get(@key)
    Process.put(@key, id_of(transaction_or_id))

    try do
      fun.()
    after
      if previous, do: Process.put(@key, previous), else: Process.delete(@key)
    end
  end

  @doc """
  Make `transaction_or_id` current for the rest of this process — for a
  request process (a Plug pipeline) that ends with the request.
  """
  def put_current(transaction_or_id) do
    Process.put(@key, id_of(transaction_or_id))
    :ok
  end

  @doc "The id of the transaction this process is running in, if any."
  def current_id, do: Process.get(@key)

  @doc false
  def new_id do
    <<a::32, b::16, _::4, c::12, _::2, d::62>> = :crypto.strong_rand_bytes(16)

    <<a::32, b::16, 4::4, c::12, 2::2, d::62>>
    |> Base.encode16(case: :lower)
    |> then(fn hex ->
      Enum.join(
        [
          binary_part(hex, 0, 8),
          binary_part(hex, 8, 4),
          binary_part(hex, 12, 4),
          binary_part(hex, 16, 4),
          binary_part(hex, 20, 12)
        ],
        "-"
      )
    end)
  end

  defp id_of(%{"id" => id}), do: id
  defp id_of(id) when is_binary(id), do: id

  defp base(kind, opts) do
    %{
      "id" => Keyword.get_lazy(opts, :id, &new_id/0),
      "kind" => kind,
      "duration_ms" => Keyword.get(opts, :duration_ms, 0),
      "spans" => Keyword.get(opts, :spans, [])
    }
    |> maybe_put("status_code", Keyword.get(opts, :status_code))
    |> maybe_put("environment", Keyword.get(opts, :environment))
    |> maybe_put("occurred_at", Keyword.get(opts, :occurred_at))
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
