defmodule Errorgap.ConfigurationTest do
  use ExUnit.Case, async: false

  alias Errorgap.Configuration

  @env_keys [:endpoint, :project_slug, :project_id, :api_key, :environment, :release, :async, :filter_keys, :timeout, :root_directory]

  setup do
    original = Application.get_all_env(:errorgap)
    Enum.each(@env_keys, &Application.delete_env(:errorgap, &1))
    System.delete_env("ERRORGAP_ENDPOINT")
    System.delete_env("ERRORGAP_PROJECT_SLUG")
    System.delete_env("ERRORGAP_API_KEY")

    on_exit(fn ->
      Enum.each(@env_keys, &Application.delete_env(:errorgap, &1))
      Application.put_all_env(errorgap: original)
    end)

    :ok
  end

  test "defaults when nothing provided" do
    cfg = Configuration.build()
    assert cfg.endpoint == "http://127.0.0.1:3030"
    assert cfg.async == true
    assert "password" in cfg.filter_keys
  end

  test "reads application env" do
    Application.put_env(:errorgap, :project_slug, "demo")
    Application.put_env(:errorgap, :api_key, "flk_test")
    cfg = Configuration.build()
    assert cfg.project_slug == "demo"
    assert cfg.api_key == "flk_test"
  end

  test "validate! raises without project_slug" do
    Application.delete_env(:errorgap, :project_slug)
    cfg = Configuration.build()
    assert_raise ArgumentError, ~r/project_slug/, fn -> Configuration.validate!(cfg) end
  end

  test "validate! passes with project_slug" do
    Application.put_env(:errorgap, :project_slug, "demo")
    cfg = Configuration.build()
    assert Configuration.validate!(cfg) == cfg
  end
end
