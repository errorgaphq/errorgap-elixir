defmodule Errorgap.ApmTest do
  use ExUnit.Case, async: true

  alias Errorgap.{Span, Transaction}

  test "normalize_sql replaces literals and collapses whitespace" do
    assert Span.normalize_sql("SELECT * FROM orders WHERE id = 42 AND name = 'alice'") ==
             "SELECT * FROM orders WHERE id = ? AND name = ?"

    assert Span.normalize_sql("SELECT\n  1\n  FROM   t") == "SELECT ? FROM t"
  end

  test "database span shape" do
    span =
      Span.database("SELECT * FROM t WHERE id = 7", 12.5,
        file: "repo.ex",
        line: 20,
        function: "Repo.load/1"
      )

    assert span["kind"] == "db"
    assert span["sql"] == "SELECT * FROM t WHERE id = ?"
    assert span["duration_ms"] == 12.5
    assert span["file"] == "repo.ex"
    assert span["line"] == 20
    assert span["fn_name"] == "Repo.load/1"
  end

  test "external span shape" do
    span = Span.external(88.0, function: "Gateway.charge/1")
    assert span["kind"] == "http"
    assert span["duration_ms"] == 88.0
    refute Map.has_key?(span, "sql")
    assert span["fn_name"] == "Gateway.charge/1"
  end

  test "web transaction shape" do
    spans = [Span.database("SELECT 1", 3.0), Span.external(50.0)]

    txn =
      Transaction.web("POST", "/orders/{id}", "/orders/7",
        status_code: 201,
        duration_ms: 120.0,
        spans: spans
      )

    assert txn["kind"] == "web"
    assert txn["path"] == "/orders/{id}"
    assert txn["path_raw"] == "/orders/7"
    assert txn["status_code"] == 201
    assert length(txn["spans"]) == 2
  end

  test "job transaction shape" do
    txn = Transaction.job("ReceiptJob", "mailers", duration_ms: 40.0)
    assert txn["kind"] == "job"
    assert txn["job_class"] == "ReceiptJob"
    assert txn["queue"] == "mailers"
  end
end
