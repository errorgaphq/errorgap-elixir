# errorgap (Elixir)

Elixir notifier for [Errorgap](https://errorgap.com). Reports exceptions
from Plug/Phoenix apps, OTP processes, and plain Elixir scripts.

Requires Elixir 1.15+ and OTP 26+.

## Install

```elixir
def deps do
  [{:errorgap, "~> 0.1"}]
end
```

## Configure

`config/runtime.exs`:

```elixir
config :errorgap,
  endpoint: System.get_env("ERRORGAP_ENDPOINT"),
  project_slug: System.get_env("ERRORGAP_PROJECT_SLUG"),
  api_key: System.get_env("ERRORGAP_API_KEY"),
  environment: System.get_env("APP_ENV", "production")
```

Falls back to `ERRORGAP_*` environment variables when keys are omitted.

## Manual notification

```elixir
try do
  risky()
rescue
  exc ->
    Errorgap.notify(exc, stacktrace: __STACKTRACE__, context: %{component: "billing"})
    reraise exc, __STACKTRACE__
end
```

## Phoenix / Plug

Use `Plug.ErrorHandler` and delegate to `Errorgap.Plug.report/2`:

```elixir
defmodule MyAppWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :my_app
  use Plug.ErrorHandler

  # ... plugs ...

  @impl Plug.ErrorHandler
  def handle_errors(conn, error_info) do
    Errorgap.Plug.report(conn, error_info)
    conn
  end
end
```

## Configuration reference

| Key | Default | Notes |
|---|---|---|
| `:endpoint` | `ERRORGAP_ENDPOINT` or `http://127.0.0.1:3030` | |
| `:project_slug` | `ERRORGAP_PROJECT_SLUG` | **Required** |
| `:project_id` | `ERRORGAP_PROJECT_ID` | |
| `:api_key` | `ERRORGAP_API_KEY` | Sent as `x-errorgap-project-key` |
| `:environment` | `ERRORGAP_ENVIRONMENT` or `production` | |
| `:release` | `ERRORGAP_RELEASE` | |
| `:async` | `true` | Cast to a GenServer worker |
| `:filter_keys` | `["password", "token", ...]` | Substring, case-insensitive |
| `:timeout` | `5_000` | HTTP timeout (ms) |

## Graceful flush

```elixir
Errorgap.flush(5_000)
```

## Development

```sh
mix deps.get
mix test
```

## License

MIT.
