defmodule Errorgap.Configuration do
  @moduledoc """
  Reads the runtime configuration from the `:errorgap` application env, with
  `ERRORGAP_*` environment variables as defaults.
  """

  @default_filter_keys ~w(password password_confirmation token secret api_key authorization cookie)

  @type t :: %__MODULE__{
          endpoint: String.t(),
          project_slug: String.t() | nil,
          project_id: String.t() | nil,
          api_key: String.t() | nil,
          environment: String.t(),
          release: String.t() | nil,
          async: boolean(),
          filter_keys: [String.t()],
          timeout: pos_integer(),
          root_directory: String.t(),
          apm_enabled: boolean(),
          apm_sample_rate: float(),
          logs_enabled: boolean(),
          minimum_log_level: String.t(),
          max_breadcrumbs: non_neg_integer()
        }

  defstruct endpoint: nil,
            project_slug: nil,
            project_id: nil,
            api_key: nil,
            environment: nil,
            release: nil,
            async: true,
            filter_keys: @default_filter_keys,
            timeout: 5_000,
            root_directory: nil,
            apm_enabled: true,
            apm_sample_rate: 1.0,
            logs_enabled: true,
            minimum_log_level: "info",
            max_breadcrumbs: 25

  @doc "Build a Configuration from application env + ERRORGAP_* env vars."
  def build do
    env = Application.get_all_env(:errorgap)

    %__MODULE__{
      endpoint: get(env, :endpoint, "ERRORGAP_ENDPOINT", "http://127.0.0.1:3030"),
      project_slug: get(env, :project_slug, "ERRORGAP_PROJECT_SLUG", nil),
      project_id: get(env, :project_id, "ERRORGAP_PROJECT_ID", nil),
      api_key: get(env, :api_key, "ERRORGAP_API_KEY", nil),
      environment: get(env, :environment, "ERRORGAP_ENVIRONMENT", "production"),
      release: get(env, :release, "ERRORGAP_RELEASE", nil),
      async: Keyword.get(env, :async, true),
      filter_keys: Keyword.get(env, :filter_keys, @default_filter_keys),
      timeout: Keyword.get(env, :timeout, 5_000),
      root_directory: get(env, :root_directory, "PWD", File.cwd!()),
      apm_enabled: Keyword.get(env, :apm_enabled, true),
      apm_sample_rate: Keyword.get(env, :apm_sample_rate, 1.0) |> clamp_rate(),
      logs_enabled: Keyword.get(env, :logs_enabled, true),
      minimum_log_level: get(env, :minimum_log_level, "ERRORGAP_MIN_LOG_LEVEL", "info"),
      max_breadcrumbs: Keyword.get(env, :max_breadcrumbs, 25)
    }
  end

  defp clamp_rate(rate) when is_number(rate), do: rate |> max(0.0) |> min(1.0) |> :erlang.float()
  defp clamp_rate(_), do: 1.0

  def validate!(%__MODULE__{} = config) do
    case config.project_slug do
      nil -> raise ArgumentError, "Errorgap project_slug is required"
      "" -> raise ArgumentError, "Errorgap project_slug is required"
      _ -> :ok
    end

    if config.endpoint in [nil, ""] do
      raise ArgumentError, "Errorgap endpoint is required"
    end

    config
  end

  defp get(env, key, env_var, default) do
    Keyword.get(env, key) || System.get_env(env_var) || default
  end
end
