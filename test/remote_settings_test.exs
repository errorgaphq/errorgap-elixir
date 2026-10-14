defmodule Errorgap.RemoteSettingsTest do
  use ExUnit.Case, async: false

  alias Errorgap.{Client, Configuration}

  # A one-connection-at-a-time server answering every request with `body`.
  defp serve(status, body) do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, packet: :raw])
    {:ok, port} = :inet.port(listen)

    pid =
      spawn(fn ->
        Stream.repeatedly(fn -> :gen_tcp.accept(listen) end)
        |> Enum.each(fn
          {:ok, sock} ->
            :gen_tcp.recv(sock, 0, 1_000)

            :gen_tcp.send(
              sock,
              "HTTP/1.1 #{status} X\r\nContent-Length: #{byte_size(body)}\r\nConnection: close\r\n\r\n#{body}"
            )

            :gen_tcp.close(sock)

          _ ->
            exit(:normal)
        end)
      end)

    on_exit(fn ->
      :gen_tcp.close(listen)
      Process.exit(pid, :kill)
      Client.forget_remote_settings()
    end)

    %Configuration{Configuration.build() | endpoint: "http://127.0.0.1:#{port}", project_slug: "demo", remote_settings: true}
  end

  test "a switched-off kind is not sent, and the rest is" do
    config = serve(200, ~s({"errors_enabled":false,"apm_enabled":true,"poll_interval_seconds":600}))

    assert Client.remote_enabled?(:notices, config), "everything is on until errorgap says otherwise"
    assert Client.refresh_remote_settings(config)
    refute Client.remote_enabled?(:notices, config)
    assert Client.remote_enabled?(:transactions, config)
    assert Client.remote_enabled?(:logs, config)
  end

  test "everything stays on when the settings cannot be read or the option is off" do
    config = serve(500, "nope")
    refute Client.refresh_remote_settings(config)
    assert Client.remote_enabled?(:notices, config)

    refute Client.refresh_remote_settings(%Configuration{config | endpoint: "http://127.0.0.1:1"})
    assert Client.remote_enabled?(:notices, %Configuration{config | remote_settings: false})
  end
end
