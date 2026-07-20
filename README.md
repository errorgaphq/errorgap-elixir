# errorgap (Elixir)

Elixir notifier for [Errorgap](https://errorgap.com). Reports exceptions
from Plug/Phoenix apps, OTP processes, and plain Elixir scripts — with
source-aware backtraces, nested causes, breadcrumbs, structured logs, and APM
transactions.

Backtrace frames are resolved against the project source tree — file, line,
function, an app-versus-dependency flag, and a surrounding source excerpt — so
the dashboard renders highlighted source without any repository integration.

Requires Elixir 1.15+ and OTP 26+.

## Install

```elixir
def deps do
  [{:errorgap, "~> 0.2"}]
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

## OTP crash reports

Attach the `:logger` handler once at startup so unhandled exceptions in
supervised processes are captured automatically:

```elixir
Errorgap.LoggerHandler.attach()
```

## Causes

Wrap an exception with a `:cause` field (or pass `cause:`) and each cause's
type/message lands in `context.causes`:

```elixir
Errorgap.notify(%MyApp.CheckoutError{message: "checkout failed", cause: db_error},
  stacktrace: __STACKTRACE__)
```

## Breadcrumbs

Breadcrumbs accumulate per-process and attach to notices as
`context.breadcrumbs`:

```elixir
Errorgap.add_breadcrumb("loaded checkout", "navigation", %{from: "cart"})
```

## Structured logs

```elixir
Errorgap.log("payment gateway timeout", "error", "payments")
```

Levels are `trace < debug < info < warn < error < fatal`; anything below
`:minimum_log_level` is dropped client-side.

## Performance (APM)

```elixir
alias Errorgap.{Span, Transaction}

spans = [
  Span.database("SELECT * FROM orders WHERE id = 123", 4.2, function: "OrderRepo.get/1"),
  Span.external(88.0, function: "PaymentGateway.charge/1")
]

Transaction.web("GET", "/orders/{id}", "/orders/123", status_code: 200, duration_ms: 120.0, spans: spans)
|> Errorgap.notify_transaction()

# Background work:
Transaction.job("ReceiptJob", "mailers", duration_ms: 40.0)
|> Errorgap.notify_transaction()
```

`path` is the normalized route template used for grouping; `path_raw` is the
concrete URL. APM delivery requires `:apm_enabled` (default `true`).

## Configuration reference

| Key | Default | Notes |
|---|---|---|
| `:endpoint` | `ERRORGAP_ENDPOINT` or `http://127.0.0.1:3030` | |
| `:project_slug` | `ERRORGAP_PROJECT_SLUG` | **Required** |
| `:project_id` | `ERRORGAP_PROJECT_ID` | |
| `:api_key` | `ERRORGAP_API_KEY` | Sent as `x-errorgap-project-key` |
| `:environment` | `ERRORGAP_ENVIRONMENT` or `production` | |
| `:release` | `ERRORGAP_RELEASE` | |
| `:root_directory` | `PWD` or `File.cwd!()` | Resolves backtrace source files |
| `:async` | `true` | Cast to a GenServer worker |
| `:filter_keys` | `["password", "token", ...]` | Substring, case-insensitive |
| `:timeout` | `5_000` | HTTP timeout (ms) |
| `:apm_enabled` | `true` | Deliver APM transactions |
| `:apm_sample_rate` | `1.0` | Fraction (0..1) of transactions delivered |
| `:logs_enabled` | `true` | Deliver structured logs |
| `:minimum_log_level` | `"info"` | Drop logs below this level |
| `:max_breadcrumbs` | `25` | Breadcrumbs retained per notice |

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
