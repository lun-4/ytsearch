defmodule YtSearch.Tinycron do
  use GenServer
  require Logger

  def new(module, opts \\ []) do
    %{
      id: module,
      start: {__MODULE__, :start_link, [module, opts |> Keyword.put(:name, module)]}
    }
  end

  def start_link(module, opts \\ []) do
    GenServer.start_link(__MODULE__, [module, opts], opts)
  end

  def noop(mod, value) do
    GenServer.cast(mod, {:noop, value})
  end

  @impl true
  def init([module, opts]) do
    state = %{module: module, opts: opts}
    schedule_work(state)
    {:ok, state}
  end

  @impl true
  def handle_info(:work, %{module: module} = state) do
    unless state |> Map.get(:noop, false) do
      Logger.debug("running #{inspect(state.module)}")
      module.tick()
    end

    schedule_work(state)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:noop, value}, state) do
    {:noreply, state |> Map.put(:noop, value)}
  end

  defp schedule_work(state) do
    every_seconds = state.opts |> Keyword.get(:every) || 10
    jitter_seconds_range = state.opts |> Keyword.get(:jitter) || -2..2
    first..last//step = jitter_seconds_range
    # turn it into milliseconds for greater jitter possibilities
    jitter_milliseconds_range = (first * 1000)..(last * 1000)//step

    # prevent jitter from creating negative next_tick_time by doing max(0, next_tick_time)
    next_tick_time = max(0, every_seconds * 1000 + Enum.random(jitter_milliseconds_range))
    Logger.debug("scheduling #{inspect(state.module)} in #{next_tick_time}ms")
    Process.send_after(self(), :work, next_tick_time)
  end
end
