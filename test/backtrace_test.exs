defmodule Errorgap.BacktraceTest do
  use ExUnit.Case, async: true

  alias Errorgap.Backtrace

  test "decodes frames with file, line, and function" do
    stacktrace = [
      {MyApp.Checkout, :call, 1, [file: ~c"lib/my_app/checkout.ex", line: 42]}
    ]

    [frame] = Backtrace.from_stacktrace(stacktrace, "/app")
    assert frame["file"] == "lib/my_app/checkout.ex"
    assert frame["line"] == 42
    assert frame["function"] == "MyApp.Checkout.call/1"
    assert frame["in_app"] == true
    assert frame["index"] == 0
  end

  test "classifies deps and stdlib frames as not in_app" do
    stacktrace = [
      {Plug.Conn, :send_resp, 1, [file: ~c"deps/plug/lib/plug/conn.ex", line: 1]},
      {Enum, :map, 2, [file: ~c"lib/elixir/lib/enum.ex", line: 1]}
    ]

    [dep, stdlib] = Backtrace.from_stacktrace(stacktrace, "/app")
    assert dep["in_app"] == false
    assert stdlib["in_app"] == false
  end

  test "drops frames without a resolvable file" do
    stacktrace = [
      {:errorgap_no_such_module_xyz, :call, 1, []},
      {MyApp.Pricing, :compute, 1, [file: ~c"lib/my_app/pricing.ex", line: 5]}
    ]

    frames = Backtrace.from_stacktrace(stacktrace, "/app")
    assert length(frames) == 1
    assert hd(frames)["function"] == "MyApp.Pricing.compute/1"
    assert hd(frames)["index"] == 0
  end

  test "attaches a source excerpt for a readable app file" do
    stacktrace = [
      {Errorgap.Backtrace, :from_stacktrace, 2, [file: ~c"lib/errorgap/backtrace.ex", line: 1]}
    ]

    [frame] = Backtrace.from_stacktrace(stacktrace, File.cwd!())
    assert frame["in_app"] == true
    assert %{"start_line" => 1, "lines" => lines} = frame["source"]
    assert Enum.any?(lines, &String.contains?(&1, "Errorgap.Backtrace"))
  end
end
