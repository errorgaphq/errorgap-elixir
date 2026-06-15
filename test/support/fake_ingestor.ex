defmodule Errorgap.FakeIngestor do
  @moduledoc false

  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc "Like `start_link/1` but not linked to the caller — for ExUnit setup."
  def start(opts \\ []) do
    GenServer.start(__MODULE__, opts)
  end

  def endpoint(pid), do: GenServer.call(pid, :endpoint)
  def requests(pid), do: GenServer.call(pid, :requests)
  def stop(pid), do: GenServer.stop(pid)

  @impl true
  def init(_opts) do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, packet: :http])
    {:ok, port} = :inet.port(listen)
    parent = self()
    Task.start_link(fn -> accept_loop(parent, listen) end)
    {:ok, %{port: port, listen: listen, requests: []}}
  end

  @impl true
  def handle_call(:endpoint, _from, state), do: {:reply, "http://127.0.0.1:#{state.port}", state}
  def handle_call(:requests, _from, state), do: {:reply, Enum.reverse(state.requests), state}

  @impl true
  def handle_cast({:request, req}, state) do
    {:noreply, %{state | requests: [req | state.requests]}}
  end

  @impl true
  def terminate(_reason, state), do: :gen_tcp.close(state.listen)

  defp accept_loop(parent, listen) do
    case :gen_tcp.accept(listen) do
      {:ok, sock} ->
        Task.start(fn -> handle_conn(parent, sock) end)
        accept_loop(parent, listen)

      {:error, _} ->
        :ok
    end
  end

  defp handle_conn(parent, sock) do
    {method, path, headers} = read_request(sock, %{})
    content_length = Map.get(headers, "content-length", "0") |> String.to_integer()

    body =
      if content_length > 0 do
        :inet.setopts(sock, packet: :raw)
        case :gen_tcp.recv(sock, content_length) do
          {:ok, data} -> data
          _ -> ""
        end
      else
        ""
      end

    GenServer.cast(parent, {:request, %{method: method, path: path, headers: headers, body: body}})

    response =
      "HTTP/1.1 201 Created\r\nContent-Type: application/json\r\nContent-Length: 18\r\nConnection: close\r\n\r\n{\"group_id\":\"g_1\"}"

    :gen_tcp.send(sock, response)
    :gen_tcp.close(sock)
  end

  defp read_request(sock, headers) do
    case :gen_tcp.recv(sock, 0) do
      {:ok, {:http_request, method, {:abs_path, path}, _}} ->
        read_headers(sock, to_string(method), to_string(path), headers)

      _ ->
        {"", "", %{}}
    end
  end

  defp read_headers(sock, method, path, headers) do
    case :gen_tcp.recv(sock, 0) do
      {:ok, {:http_header, _, name, _, value}} ->
        key = name |> to_string() |> String.downcase()
        read_headers(sock, method, path, Map.put(headers, key, to_string(value)))

      {:ok, :http_eoh} ->
        {method, path, headers}

      _ ->
        {method, path, headers}
    end
  end
end
