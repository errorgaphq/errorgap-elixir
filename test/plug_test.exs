defmodule Errorgap.PlugTest do
  use ExUnit.Case, async: false

  alias Errorgap.FakeIngestor

  defmodule Router do
    use Plug.Router
    use Plug.ErrorHandler

    plug(Errorgap.Plug, apm: true)
    plug(:match)
    plug(:dispatch)

    get "/orders/:id" do
      Errorgap.notify(%RuntimeError{message: "card declined"}, sync: true)
      send_resp(conn, 201, "ok")
    end

    get "/boom/:id" do
      _ = conn
      raise "kaboom"
    end

    @impl Plug.ErrorHandler
    def handle_errors(conn, error) do
      Errorgap.Plug.report(conn, error)
    end
  end

  setup do
    {:ok, ing} = FakeIngestor.start()
    Application.put_env(:errorgap, :endpoint, FakeIngestor.endpoint(ing))
    Application.put_env(:errorgap, :project_slug, "demo")
    Application.put_env(:errorgap, :async, false)
    Application.put_env(:errorgap, :apm_enabled, true)
    Application.put_env(:errorgap, :apm_sample_rate, 1.0)

    on_exit(fn ->
      for key <- [:endpoint, :project_slug, :async, :apm_enabled, :apm_sample_rate],
          do: Application.delete_env(:errorgap, key)

      FakeIngestor.stop(ing)
    end)

    %{ingestor: ing}
  end

  defp bodies(ing, suffix) do
    ing
    |> FakeIngestor.requests()
    |> Enum.filter(&String.ends_with?(&1.path, suffix))
    |> Enum.map(& &1.body)
  end

  # Errorgap.JSON only encodes; read the fields the assertions need.
  defp field(body, key) do
    case Regex.run(~r/"#{key}":("([^"]*)"|\d+)/, body) do
      [_, _, string] when string != "" -> string
      [_, number] -> String.to_integer(number)
      _ -> nil
    end
  end

  test "records requests with their route, status and browser trace, linking errors", %{
    ingestor: ing
  } do
    conn =
      Plug.Test.conn(:get, "/orders/7?x=1")
      |> Plug.Conn.put_req_header("x-errorgap-trace", "0192F3C4-7A1B-4C2D-9E3F-0123456789AB")
      |> Router.call(Router.init([]))

    assert conn.status == 201

    assert_raise Plug.Conn.WrapperError, fn ->
      Plug.Test.conn(:get, "/boom/1") |> Router.call(Router.init([]))
    end

    [ok, boom] = bodies(ing, "/transactions")
    assert field(ok, "path") == "/orders/:id"
    assert field(ok, "path_raw") == "/orders/7"
    assert field(ok, "status_code") == 201
    assert field(ok, "trace_id") == "0192f3c4-7a1b-4c2d-9e3f-0123456789ab"
    assert field(boom, "path") == "/boom/:id"
    assert field(boom, "status_code") == 500
    assert field(boom, "trace_id") == nil

    by_message =
      for n <- bodies(ing, "/notices"),
          into: %{},
          do: {field(n, "message"), field(n, "transaction_id")}

    assert by_message["card declined"] == field(ok, "id")
    assert by_message["kaboom"] == field(boom, "id")
  end

  test "without apm: true the plug records nothing", %{ingestor: ing} do
    conn = Plug.Test.conn(:get, "/x") |> Errorgap.Plug.call(Errorgap.Plug.init([]))
    Plug.Conn.send_resp(conn, 200, "ok")
    assert bodies(ing, "/transactions") == []
  end
end
