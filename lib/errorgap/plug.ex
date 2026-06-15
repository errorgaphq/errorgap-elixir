if Code.ensure_loaded?(Plug) do
  defmodule Errorgap.Plug do
    @moduledoc """
    A `Plug` that reports unhandled exceptions to Errorgap. Add to the top
    of your Phoenix endpoint:

        plug Errorgap.Plug
    """

    @behaviour Plug

    @impl Plug
    def init(opts), do: opts

    @impl Plug
    def call(conn, _opts) do
      Plug.Conn.register_before_send(conn, & &1)
    rescue
      _ -> conn
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
