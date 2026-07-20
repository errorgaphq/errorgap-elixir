defmodule Errorgap.BreadcrumbsTest do
  use ExUnit.Case, async: false

  alias Errorgap.Breadcrumbs

  setup do
    Breadcrumbs.clear()
    on_exit(&Breadcrumbs.clear/0)
    :ok
  end

  test "records message, category, and metadata with a timestamp" do
    Breadcrumbs.add("tapped Checkout", "ui", %{"screen" => "Cart"}, 10)
    [crumb] = Breadcrumbs.get()
    assert crumb["message"] == "tapped Checkout"
    assert crumb["category"] == "ui"
    assert crumb["metadata"] == %{"screen" => "Cart"}
    assert is_binary(crumb["timestamp"])
  end

  test "drops the oldest beyond capacity" do
    for i <- 0..4, do: Breadcrumbs.add("event #{i}", nil, %{}, 3)
    messages = Breadcrumbs.get() |> Enum.map(& &1["message"])
    assert messages == ["event 2", "event 3", "event 4"]
  end

  test "keeps nothing when capacity is zero" do
    Breadcrumbs.add("ignored", nil, %{}, 0)
    assert Breadcrumbs.get() == []
  end

  test "clear empties the buffer" do
    Breadcrumbs.add("one")
    Breadcrumbs.clear()
    assert Breadcrumbs.get() == []
  end
end
