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

  test "a notice inside a transaction carries its id", %{ingestor: ing} do
    txn = Errorgap.Transaction.web("GET", "/orders/{id}", "/orders/7")
    id = txn["id"]
    assert id =~ ~r/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/

    Errorgap.with_transaction(txn, fn ->
      Errorgap.notify(%RuntimeError{message: "boom"}, sync: true)
    end)

    Errorgap.notify(%RuntimeError{message: "after"}, sync: true)
    assert Errorgap.current_transaction_id() == nil

    [inside, outside] = FakeIngestor.requests(ing)
    assert inside.body =~ ~s("transaction_id":"#{id}")
    refute outside.body =~ "transaction_id"
  end

  test "an explicit transaction id is kept", %{ingestor: ing} do
    Errorgap.with_transaction("scoped", fn ->
      Errorgap.notify(%RuntimeError{message: "x"}, context: %{transaction_id: "mine"}, sync: true)
    end)

    [req] = FakeIngestor.requests(ing)
    assert req.body =~ ~s("transaction_id":"mine")
    refute req.body =~ "scoped"
  end

  test "the transaction sends its id", %{ingestor: ing} do
    Application.put_env(:errorgap, :apm_enabled, true)
    Application.put_env(:errorgap, :apm_sample_rate, 1.0)

    on_exit(fn ->
      Application.delete_env(:errorgap, :apm_enabled)
      Application.delete_env(:errorgap, :apm_sample_rate)
    end)

    txn = Errorgap.Transaction.job("ReceiptJob", "mailers", duration_ms: 4.0)
    {:ok, %{status: 201}} = Errorgap.notify_transaction(txn, sync: true)
    [req] = FakeIngestor.requests(ing)
    assert req.body =~ ~s("id":"#{txn["id"]}")
  end

  test "nested scopes restore the outer id" do
    Errorgap.with_transaction("outer", fn ->
      assert Errorgap.with_transaction("inner", &Errorgap.current_transaction_id/0) == "inner"
      assert Errorgap.current_transaction_id() == "outer"
    end)

    assert Errorgap.current_transaction_id() == nil
  end
end
