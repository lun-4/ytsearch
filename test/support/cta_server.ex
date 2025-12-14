defmodule YtSearch.Test.CTAServer do
  @moduledoc """
  Manages the CTA HTTP server for testing.
  """
  use GenServer
  require Logger

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def get_port do
    GenServer.call(__MODULE__, :get_port)
  end

  def init(_) do
    # Find a random free port
    port = find_free_port()

    # Set environment variables for the CTA extractor HTTP module
    System.put_env("CTA_HTTP_HOST", "localhost")
    System.put_env("CTA_HTTP_PORT", Integer.to_string(port))
    IO.puts("starting cta server on localhost:#{port}")

    # Start the Go server
    server_path = Path.join([File.cwd!(), "cta5", "cta_http_server"])

    port_obj =
      Port.open(
        {:spawn_executable, server_path},
        [
          :binary,
          :exit_status,
          :stderr_to_stdout,
          {:env, [{~c"PORT", String.to_charlist(Integer.to_string(port))}]}
        ]
      )

    # Verify server is running (3 second timeout, 10ms intervals)
    case wait_for_health_check(port, 300) do
      :ok ->
        Logger.info("CTA HTTP server started on port #{port}")
        {:ok, %{port: port, port_obj: port_obj}}

      {:error, reason} ->
        Logger.error("Failed to start CTA HTTP server: #{inspect(reason)}")
        Port.close(port_obj)
        {:stop, reason}
    end
  end

  def handle_call(:get_port, _from, state) do
    {:reply, state.port, state}
  end

  def handle_info({port, {:data, data}}, %{port_obj: port} = state) do
    # Log output from the Go server
    Logger.debug("CTA Server: #{data}")
    {:noreply, state}
  end

  def handle_info({port, {:exit_status, status}}, %{port_obj: port} = state) do
    Logger.warning("CTA Server exited with status: #{status}")
    {:noreply, state}
  end

  def terminate(_reason, %{port_obj: port_obj}) do
    Port.close(port_obj)
    :ok
  end

  defp find_free_port do
    # Open a TCP socket on port 0 to let the OS assign a free port
    {:ok, socket} = :gen_tcp.listen(0, [:binary, {:active, false}])
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)
    port
  end

  defp wait_for_health_check(_port, 0) do
    {:error, :timeout}
  end

  defp wait_for_health_check(port, attempts_left) do
    url = "http://localhost:#{port}/health"

    case HTTPoison.get(url, [], recv_timeout: 1000) do
      {:ok, %HTTPoison.Response{status_code: 200}} ->
        :ok

      _ ->
        Process.sleep(10)
        wait_for_health_check(port, attempts_left - 1)
    end
  end
end
