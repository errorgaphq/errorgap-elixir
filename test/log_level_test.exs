defmodule Errorgap.LogLevelTest do
  use ExUnit.Case, async: true

  alias Errorgap.LogLevel

  test "normalizes aliases" do
    assert LogLevel.normalize("WARNING") == "warn"
    assert LogLevel.normalize(:warning) == "warn"
    assert LogLevel.normalize("critical") == "error"
    assert LogLevel.normalize("notice") == "info"
    assert LogLevel.normalize("nonsense") == "info"
    assert LogLevel.normalize("fatal") == "fatal"
  end

  test "ranks order" do
    assert LogLevel.rank("trace") < LogLevel.rank("debug")
    assert LogLevel.rank("info") < LogLevel.rank("warn")
    assert LogLevel.rank("warn") < LogLevel.rank("error")
    assert LogLevel.rank("error") < LogLevel.rank("fatal")
  end
end
