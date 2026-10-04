if Code.ensure_loaded?(Plug) do
  defmodule Errorgap.Plug do
    @moduledoc """
    A `Plug` that reports unhandled exceptions to Errorgap. Add to the top
    of your Phoenix endpoint:

        plug Errorgap.Plug

    With `apm: true` it also records each request as an APM transaction,
    grouped by its route (`/orders/:id`, from Phoenix or `Plug.Router`):
    errors reported while it runs carry its transaction id, and the
    `x-errorgap-trace` header sent by the errorgap browser and mobile SDKs
    links the caller's view of the request to it.

        plug Errorgap.Plug, apm: true
    """

    @behaviour Plug

    @pending {:errorgap, :plug_transaction}

    @impl Plug
    def init(opts), do: opts

    @impl Plug
    def call(conn, opts) do
      if Keyword.get(opts, :apm, false) do
        track(conn)
      else
        conn
      end
    rescue
      _ -> conn
    end

    defp track(conn) do
      trace =
        conn
        |> Plug.Conn.get_req_header(Errorgap.Transaction.trace_header())
        |> List.first()

      txn =
        Errorgap.Transaction.web(conn.method, conn.request_path, conn.request_path,
          trace_id: trace,
          occurred_at: DateTime.utc_now() |> DateTime.to_iso8601()
        )

      # One process serves the request, so errors reported from it carry
      # this transaction's id.
      Errorgap.Transaction.put_current(txn)
      Process.put(@pending, {txn, System.monotonic_time(:microsecond)})

      Plug.Conn.register_before_send(conn, fn conn ->
        finish(conn, conn.status)
        conn
      end)
    end

    # Sends the request's transaction once, from before_send or (for a
    # request that raised) from report/2.
    defp finish(conn, status) do
      case Process.delete(@pending) do
        {txn, started} ->
          duration_ms = (System.monotonic_time(:microsecond) - started) / 1000

          txn
          |> Map.merge(%{
            "path" => route(conn),
            "status_code" => status,
            "duration_ms" => duration_ms
          })
          |> Errorgap.notify_transaction()

        nil ->
          :ok
      end
    end

    @doc false
    # The matched route template: Plug.Router stores it on the conn; Phoenix
    # resolves it from the router. Falls back to the request path.
    def route(conn) do
      case conn.private do
        %{plug_route: {route, _fun}} when is_binary(route) ->
          route

        %{phoenix_router: router} ->
          phoenix_route(router, conn) || conn.request_path

        _ ->
          conn.request_path
      end
    end

    defp phoenix_route(router, conn) do
      if Code.ensure_loaded?(Phoenix.Router) and
           function_exported?(Phoenix.Router, :route_info, 4) do
        case apply(Phoenix.Router, :route_info, [
               router,
               conn.method,
               conn.request_path,
               conn.host
             ]) do
          %{route: route} when is_binary(route) -> route
          _ -> nil
        end
      end
    rescue
      _ -> nil
    end

    @doc """
    Helper for `Plug.ErrorHandler`-style modules. Pass the kind, reason,
    and stacktrace passed to `handle_errors/2`.
    """
    def report(conn, %{kind: kind, reason: reason, stack: stack}) do
      error =
        case {kind, reason} do
          {:error, %_{} = exc} -> exc
          {:error, reason} -> %RuntimeError{message: inspect(reason)}
          {:throw, value} -> %RuntimeError{message: "thrown: " <> inspect(value)}
          {:exit, reason} -> %RuntimeError{message: "exited: " <> inspect(reason)}
        end

      result =
        Errorgap.notify(error,
          stacktrace: stack,
          context: %{
            source: "Errorgap.Plug",
            url: full_url(conn),
            component: conn.request_path,
            action: conn.method
          },
          environment: %{
            method: conn.method,
            path: conn.request_path,
            query_string: conn.query_string,
            user_agent: get_header(conn, "user-agent"),
            remote_addr: format_addr(conn.remote_ip)
          }
        )

      # A request that raised never reaches before_send: record it as a 500.
      finish(conn, 500)
      result
    end

    defp full_url(conn) do
      "#{conn.scheme}://#{conn.host}#{conn.request_path}"
    end

    defp get_header(conn, name) do
      case Plug.Conn.get_req_header(conn, name) do
        [v | _] -> v
        _ -> nil
      end
    end

    defp format_addr(nil), do: nil

    defp format_addr(ip) when is_tuple(ip) do
      ip |> :inet.ntoa() |> to_string()
    end

    defp format_addr(other), do: to_string(other)
  end
end
