defmodule Errorgap.ClientTest do
  use ExUnit.Case, async: false

  alias Errorgap.FakeIngestor

  @env_keys [:endpoint, :project_slug, :project_id, :api_key, :environment, :release, :async]

  setup do
    {:ok, ing} = FakeIngestor.start()
    endpoint = FakeIngestor.endpoint(ing)

    original = Application.get_all_env(:errorgap)
    Application.put_env(:errorgap, :endpoint, endpoint)
    Application.put_env(:errorgap, :project_slug, "demo")
    Application.put_env(:errorgap, :api_key, "flk_test")
    Application.put_env(:errorgap, :async, false)

    on_exit(fn ->
      if Process.alive?(ing), do: GenServer.stop(ing, :normal, 1_000)
      Enum.each(@env_keys, &Application.delete_env(:errorgap, &1))
      Application.put_all_env(errorgap: original)
    end)

    %{ingestor: ing}
  end

  test "posts to /api/projects/:slug/notices with canonical headers", %{ingestor: ing} do
    {:ok, %{status: 201}} = Errorgap.notify(%RuntimeError{message: "boom"}, sync: true)

    [req] = FakeIngestor.requests(ing)
    assert req.method == "POST"
    assert req.path == "/api/projects/demo/notices"
    assert req.headers["x-errorgap-project-key"] == "flk_test"
    assert String.starts_with?(req.headers["user-agent"], "errorgap-elixir/")
  end

  test "sends the notice envelope", %{ingestor: ing} do
    Errorgap.notify(%RuntimeError{message: "kaboom"}, sync: true)
    [req] = FakeIngestor.requests(ing)
    assert req.body =~ ~s("type":"RuntimeError")
    assert req.body =~ ~s("message":"kaboom")
    assert req.body =~ ~s("notifier":"errorgap-elixir")
  end

  test "posts a structured log to /logs", %{ingestor: ing} do
    {:ok, %{status: 201}} = Errorgap.log("gateway timeout", "error", "payments", sync: true)

    [req] = FakeIngestor.requests(ing)
    assert req.path == "/api/projects/demo/logs"
    assert req.body =~ ~s("message":"gateway timeout")
    assert req.body =~ ~s("level":"error")
    assert req.body =~ ~s("source":"payments")
  end

  test "drops logs below the minimum level", %{ingestor: ing} do
    Application.put_env(:errorgap, :minimum_log_level, "warn")
    on_exit(fn -> Application.delete_env(:errorgap, :minimum_log_level) end)

    assert {:ok, %{status: 204}} = Errorgap.log("chatty", "info", nil, sync: true)
    assert FakeIngestor.requests(ing) == []
  end

  test "posts an APM transaction to /transactions", %{ingestor: ing} do
    txn =
      Errorgap.Transaction.web("GET", "/orders/{id}", "/orders/7",
        status_code: 200,
        duration_ms: 12.5,
        spans: [Errorgap.Span.database("SELECT 1", 3.0)]
      )

    {:ok, %{status: 201}} = Errorgap.notify_transaction(txn, sync: true)

    [req] = FakeIngestor.requests(ing)
    assert req.path == "/api/projects/demo/transactions"
    assert req.body =~ ~s("kind":"web")
    assert req.body =~ ~s("path":"/orders/{id}")
    assert req.body =~ ~s("path_raw":"/orders/7")
  end

  test "skips APM when disabled", %{ingestor: ing} do
    Application.put_env(:errorgap, :apm_enabled, false)
    on_exit(fn -> Application.delete_env(:errorgap, :apm_enabled) end)

    txn = Errorgap.Transaction.job("J", "default", duration_ms: 1.0)
    assert {:ok, %{status: 204}} = Errorgap.notify_transaction(txn, sync: true)
    assert FakeIngestor.requests(ing) == []
  end

  test "attaches process breadcrumbs to a notice", %{ingestor: ing} do
    Errorgap.clear_breadcrumbs()
    Errorgap.add_breadcrumb("opened cart", "navigation")
    Errorgap.add_breadcrumb("tapped checkout", "ui")
    on_exit(&Errorgap.clear_breadcrumbs/0)

    Errorgap.notify(%RuntimeError{message: "boom"}, sync: true)

    [req] = FakeIngestor.requests(ing)
    assert req.body =~ ~s("message":"opened cart")
    assert req.body =~ ~s("message":"tapped checkout")
  end
end
