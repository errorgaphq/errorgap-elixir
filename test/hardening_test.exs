defmodule Errorgap.HardeningTest do
  use ExUnit.Case, async: false

  alias Errorgap.{Client, FakeIngestor, Filter}

  @env_keys [:endpoint, :project_slug, :async, :before_notify, :ignore_environments, :environment]

  defp start(opts \\ []) do
    {:ok, ing} = FakeIngestor.start(opts)
    original = Application.get_all_env(:errorgap)
    Application.put_env(:errorgap, :endpoint, FakeIngestor.endpoint(ing))
    Application.put_env(:errorgap, :project_slug, "demo")
    Application.put_env(:errorgap, :async, false)

    on_exit(fn ->
      if Process.alive?(ing), do: GenServer.stop(ing, :normal, 1_000)
      Enum.each(@env_keys, &Application.delete_env(:errorgap, &1))
      Application.put_all_env(errorgap: original)
      Client.resume()
    end)

    ing
  end

  test "a 429 pauses sending for Retry-After" do
    ing = start(status: 429)

    assert {:ok, %{status: 429}} = Errorgap.notify(%RuntimeError{message: "one"}, sync: true)
    assert Client.paused?()
    assert {:error, :rate_limited} = Errorgap.notify(%RuntimeError{message: "two"}, sync: true)
    assert length(FakeIngestor.requests(ing)) == 1
  end

  test "only network and server errors are retried" do
    assert Client.retryable?({:ok, %{status: 500}})
    assert Client.retryable?({:error, :econnrefused})
    refute Client.retryable?({:ok, %{status: 422}})
    refute Client.retryable?({:ok, %{status: 429}})
    refute Client.retryable?({:error, :rate_limited})
    refute Client.retryable?({:ok, %{status: 201}})
  end

  test "before_notify can drop or change a notice, and a raising hook is skipped" do
    ing = start()

    Application.put_env(:errorgap, :before_notify, fn _notice -> false end)
    assert {:ok, %{body: "dropped by before_notify"}} =
             Errorgap.notify(%RuntimeError{message: "no"}, sync: true)

    Application.put_env(:errorgap, :before_notify, fn notice ->
      put_in(notice, ["context", "team"], "billing")
    end)

    assert {:ok, %{status: 201}} = Errorgap.notify(%RuntimeError{message: "yes"}, sync: true)

    Application.put_env(:errorgap, :before_notify, fn _notice -> raise "bug in the hook" end)
    assert {:ok, %{status: 201}} = Errorgap.notify(%RuntimeError{message: "still sent"}, sync: true)

    [changed, kept] = FakeIngestor.requests(ing)
    assert changed.body =~ ~s("team":"billing")
    assert kept.body =~ "still sent"
  end

  test "nothing is sent in an ignored environment" do
    ing = start()
    Application.put_env(:errorgap, :environment, "test")
    Application.put_env(:errorgap, :ignore_environments, ["test"])

    assert {:ok, %{body: "ignored environment"}} =
             Errorgap.notify(%RuntimeError{message: "x"}, sync: true)

    assert FakeIngestor.requests(ing) == []
  end

  test "sensitive keys are masked inside lists and in the session" do
    filtered =
      Filter.params(
        %{"users" => [%{"password" => "p", "name" => "Ada"}], "long" => String.duplicate("x", 10_000)},
        ["password"]
      )

    assert [%{"password" => "[FILTERED]", "name" => "Ada"}] = filtered["users"]
    assert String.ends_with?(filtered["long"], "[TRUNCATED]")

    ing = start()
    Errorgap.notify(%RuntimeError{message: "x"}, sync: true, session: %{"auth_token" => "t"})
    [request] = FakeIngestor.requests(ing)
    assert request.body =~ ~s("auth_token":"[FILTERED]")
  end
end
