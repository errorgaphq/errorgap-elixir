defmodule Errorgap.FilterTest do
  use ExUnit.Case, async: true

  alias Errorgap.Filter

  @defaults ~w(password token secret api_key authorization cookie)

  test "masks filtered keys" do
    out = Filter.params(%{"username" => "alice", "password" => "hunter2", "access_token" => "x"}, @defaults)
    assert out["username"] == "alice"
    assert out["password"] == "[FILTERED]"
    assert out["access_token"] == "[FILTERED]"
  end

  test "recurses into nested maps" do
    out = Filter.params(%{"user" => %{"name" => "alice", "api_key" => "x"}}, @defaults)
    assert out["user"]["name"] == "alice"
    assert out["user"]["api_key"] == "[FILTERED]"
  end

  test "case insensitive" do
    out = Filter.params(%{"Authorization" => "Bearer xyz"}, @defaults)
    assert out["Authorization"] == "[FILTERED]"
  end
end
