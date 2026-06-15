defmodule Errorgap.JSONTest do
  use ExUnit.Case, async: true

  alias Errorgap.JSON

  test "encodes maps" do
    assert JSON.encode(%{"a" => 1, "b" => "x"}) in [~s({"a":1,"b":"x"}), ~s({"b":"x","a":1})]
  end

  test "encodes lists" do
    assert JSON.encode([1, 2, 3]) == "[1,2,3]"
  end

  test "encodes nested structures" do
    assert JSON.encode(%{"k" => [1, %{"n" => true}]}) == ~s({"k":[1,{"n":true}]})
  end

  test "escapes special characters" do
    assert JSON.encode("a\nb") == ~s("a\\nb")
    assert JSON.encode(~s(a"b)) == ~s("a\\"b")
  end

  test "encodes nil booleans numbers" do
    assert JSON.encode(nil) == "null"
    assert JSON.encode(true) == "true"
    assert JSON.encode(42) == "42"
  end
end
