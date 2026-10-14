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
  [{:errorgap, "~> 0.6"}]
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

## Remote settings

Errors, performance data and logs can each be switched off for a project in
errorgap (Project settings › What SDKs send). Running nodes follow within ten
minutes, with no deploy. If errorgap cannot be reached, everything stays on.
`config :errorgap, remote_settings: false` (or `ERRORGAP_REMOTE_SETTINGS=false`)
ignores the project's switches.

## Filtering, hooks and delivery

```elixir
config :errorgap,
  ignore_environments: ["test"],
  queue_size: 100,
  # return the notice (changed or not), or false to drop it
  before_notify: {MyApp.Errorgap, :before_notify}
```

`filter_keys` are masked at any depth in `params` and `session`, inside lists
too, and oversized strings are cut. A send that fails on the network or with a
5xx is retried up to three times; after a 429 the SDK stops sending for the
server's `Retry-After`. When more than `queue_size` payloads are waiting, new
ones are refused (`{:error, :queue_full}`) instead of growing the mailbox.

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

### Request performance

Add `plug Errorgap.Plug, apm: true` near the top of your endpoint (or
`Plug.Router`) and each request is an APM transaction grouped by its route
(`/orders/:id`, from Phoenix or `Plug.Router`). Errors reported while it runs
carry its transaction id, a request that raises is recorded as a 500 by
`Errorgap.Plug.report/2`, and the `x-errorgap-trace` header sent by the
errorgap browser and mobile SDKs links the caller's view of the request to it.

```elixir
plug Errorgap.Plug, apm: true
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

### Link errors to their request

Every transaction has an id (`txn["id"]`). Run the work inside
`Errorgap.with_transaction/2` and errors reported from that process carry it
as `context.transaction_id`, so errorgap shows the error a request actually
raised on its trace and links each occurrence to its request:

```elixir
txn = Transaction.web("GET", "/orders/{id}", "/orders/123")
started = System.monotonic_time(:millisecond)
result = Errorgap.with_transaction(txn, fn -> handle(conn) end)
txn
|> Map.merge(%{"status_code" => 200, "duration_ms" => System.monotonic_time(:millisecond) - started})
|> Errorgap.notify_transaction()
```

The id lives in the process dictionary, so concurrent requests (separate
processes) never share one. In a Plug pipeline, `Errorgap.Transaction.put_current/1`
makes it current for the rest of the request process.

When the errorgap browser SDK is on the page, its API calls send an
`x-errorgap-trace` header. Pass it as `:trace_id` and errorgap's browser
Performance view links each call to the server request that answered it
(malformed values are ignored):

```elixir
trace = conn |> Plug.Conn.get_req_header("x-errorgap-trace") |> List.first()
txn = Transaction.web("GET", "/orders/{id}", conn.request_path, trace_id: trace)
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
