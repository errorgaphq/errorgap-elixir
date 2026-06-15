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
end
