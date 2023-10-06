defmodule YtSearch.SimpleRegistry do
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, nil, opts)
  end

  def get(registry, key) do
    IO.puts("get #{inspect(key)}")
    GenServer.call(registry, {:get, key})
  end

  def remove(registry, key) do
    IO.puts("remove #{inspect(key)}")
    GenServer.call(registry, {:remove, key})
  end

  @doc "only remove if pids match"
  def remove(registry, key, pid) do
    IO.puts("remove #{inspect(key)} #{inspect(pid)}")
    GenServer.call(registry, {:remove, key, pid})
  end

  def put(registry, key, pid) do
    IO.puts("put #{inspect(key)} #{inspect(pid)}")
    GenServer.call(registry, {:put, key, pid})
  end

  def whereis_name({registry, key}), do: get(registry, key) || :undefined
  def register_name({registry, key}, pid), do: put(registry, key, pid)
  def unregister_name({registry, key}), do: remove(registry, key)

  def send({registry, key}, msg) do
    pid = get(registry, key)

    if pid != nil do
      Kernel.send(pid, msg)
    end
  end

  defmodule State do
    defstruct [:version, :data, :refs]
  end

  @impl true
  def init(nil) do
    {:ok, %State{version: 0, data: %{}, refs: %{}}}
  end

  @impl true
  def handle_call({:get, key}, _from, state) do
    {:reply,
     state.data
     |> Map.get(key), state}
  end

  @impl true
  def handle_call({:remove, key}, _from, state) do
    {pid, new_data} =
      state.data
      |> Map.pop(key)

    if pid != nil do
      {:reply, :ok, %{state | data: new_data}}
    else
      {:reply, {:error, :unknown_key}, state}
    end
  end

  @impl true
  def handle_call({:remove, key, pid_check}, _from, state) do
    {pid, new_data} =
      state.data
      |> Map.pop(key)

    if pid == pid_check do
      # good
      {:reply, :ok, %{state | data: new_data}}
    else
      # revert -- use old state
      Logger.warning(
        "simple registry #{inspect(key)}, pid_check = #{inspect(pid_check)}, found pid = #{inspect(pid)}, ignoring."
      )

      {:reply, {:error, :race_condition}, state}
    end
  end

  @impl true
  def handle_call({:put, key, pid}, _from, state) do
    existing_pid = Map.get(state.data, key)

    if existing_pid == nil do
      new_data =
        state.data
        |> Map.put(key, pid)

      ref = Process.monitor(pid)
      new_refs = Map.put(state.refs, ref, key)

      {:reply, :yes, %{state | refs: new_refs, data: new_data}}
    else
      {:reply, :no, state}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    {key, new_refs} = Map.pop(state.refs, ref)
    {pid, new_data} = Map.pop(state.data, key)

    Logger.debug(
      "simple registry #{inspect(key)}, #{inspect(pid)} is down, reason #{inspect(reason)}"
    )

    {:noreply, %{state | refs: new_refs, data: new_data}}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Unexpected message; #{inspect(msg)}")
    {:noreply, state}
  end
end
