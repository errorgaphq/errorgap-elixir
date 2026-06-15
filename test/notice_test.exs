defmodule Errorgap.NoticeTest do
  use ExUnit.Case, async: true

  alias Errorgap.{Configuration, Notice}

  defp config do
    %Configuration{
      endpoint: "https://e.example.com",
      project_slug: "demo",
      project_id: "p_1",
      environment: "test",
      release: "1.2.3",
      root_directory: "/app",
      filter_keys: ~w(password token)
    }
  end

  test "captures type and message" do
    notice = Notice.build(%RuntimeError{message: "boom"}, [], config())
    [err] = notice["errors"]
    assert err["type"] == "RuntimeError"
    assert err["message"] == "boom"
  end

  test "includes notifier identification" do
    notice = Notice.build(%RuntimeError{message: "x"}, [], config())
    ctx = notice["context"]
    assert ctx["notifier"] == "errorgap-elixir"
    assert ctx["notifier_version"] == Errorgap.version()
    assert ctx["environment"] == "test"
    assert ctx["release"] == "1.2.3"
  end

  test "filters sensitive params" do
    notice = Notice.build(%RuntimeError{message: "x"}, [params: %{"username" => "alice", "password" => "hunter2"}], config())
    assert notice["params"]["username"] == "alice"
    assert notice["params"]["password"] == "[FILTERED]"
  end

  test "includes project_id" do
    notice = Notice.build(%RuntimeError{message: "x"}, [], config())
    assert notice["project_id"] == "p_1"
  end
end
