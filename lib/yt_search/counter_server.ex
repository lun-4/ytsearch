defmodule YtSearch.CounterServer do
  use GenServer
  require Logger
  alias YtSearch.Counter
  alias YtSearch.BoundedQueue

  # 10s
  @batch_interval 10_000
  # 1s
  @snapshot_interval 1000
  @max_snapshot_size 600

  defstruct [
    :pending_delta,
    :snapshots
  ]

  def start_link(_opts) do
    GenServer.start_link(
      __MODULE__,
      %__MODULE__{pending_delta: 0, snapshots: YtSearch.BoundedQueue.new(@max_snapshot_size)},
      name: __MODULE__
    )
  end

  @spec increment(number()) :: :ok
  def increment(delta) when is_number(delta) do
    GenServer.cast(__MODULE__, {:increment, delta})
  end

  @spec get_value() :: map()
  def get_value() do
    GenServer.call(__MODULE__, :get_value)
  end

  ## prom metrics

  defmodule Metrics do
    use Prometheus.Metric

    def setup() do
      Counter.declare(
        name: :yts_global_counter,
        help: "hehehe number (incremented on request)"
      )

      Gauge.declare(
        name: :yts_global_counter_db,
        help: "hehehe number (from db)"
      )
    end

    def increment(value) do
      Counter.inc(
        [name: :yts_global_counter],
        value
      )
    end

    def set_db(value) do
      Gauge.set(
        [name: :yts_global_counter_db],
        value
      )
    end
  end

  ## GenServer callbacks

  @impl true
  def init(state) do
    Logger.info("CounterServer started")

    Process.send_after(self(), :flush_to_db, @batch_interval)
    Process.send_after(self(), :snapshot, @snapshot_interval)
    {:ok, state}
  end

  @impl true
  def handle_cast(
        {:increment, delta},
        %__MODULE__{pending_delta: pending_delta} = state
      ) do
    YtSearch.CounterServer.Metrics.increment(delta)
    new_pending_delta = pending_delta + round(delta)
    {:noreply, %{state | pending_delta: new_pending_delta}}
  end

  @impl true
  def handle_call(:get_value, _from, state) do
    # Get current value from database and add any pending delta, return as float for JSON
    db_value = Counter.get_value()
    current_value = db_value + state.pending_delta

    YtSearch.CounterServer.Metrics.set_db(db_value)
    timestamp = System.os_time(:millisecond) / 1000

    {:reply,
     %{
       time: timestamp,
       counter: current_value,
       snapshots:
         state.snapshots
         |> BoundedQueue.to_list()
         |> Enum.map(fn {t, c} -> %{t: t, c: c} end)
     }, state}
  end

  @impl true
  def handle_info(:flush_to_db, %__MODULE__{pending_delta: pending_delta} = state) do
    Logger.debug("Flushing counter delta #{pending_delta} to database")

    if pending_delta != 0 do
      new_counter_entity = Counter.increment(pending_delta)
      YtSearch.CounterServer.Metrics.set_db(new_counter_entity.value)
    end

    Process.send_after(self(), :flush_to_db, @batch_interval)
    {:noreply, %{state | pending_delta: 0}}
  end

  @impl true
  def handle_info(:snapshot, %__MODULE__{} = state) do
    db_value = Counter.get_value()
    current_value = db_value + state.pending_delta
    timestamp = System.os_time(:millisecond) / 1000
    snapshot = {timestamp, current_value}
    Process.send_after(self(), :snapshot, @snapshot_interval)
    {:noreply, Map.put(state, :snapshots, BoundedQueue.enqueue(state.snapshots, snapshot))}
  end

  @impl true
  def terminate(_reason, %__MODULE__{pending_delta: pending_delta}) do
    # Flush any remaining delta to database on shutdown
    if pending_delta != 0 do
      Logger.info("Flushing remaining counter delta #{pending_delta} on shutdown")

      try do
        Counter.increment(pending_delta)
      rescue
        e ->
          Logger.error("Failed to flush counter on shutdown: #{inspect(e)}")
      end
    end

    :ok
  end
end
