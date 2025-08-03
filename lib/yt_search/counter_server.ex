defmodule YtSearch.CounterServer do
  use GenServer
  require Logger
  alias YtSearch.Counter

  # 10 seconds in milliseconds
  @batch_interval 10_000

  defstruct [
    :previous_delta,
    :pending_delta
  ]

  def start_link(_opts) do
    GenServer.start_link(
      __MODULE__,
      %__MODULE__{previous_delta: 0, pending_delta: 0},
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

    {:reply,
     %{
       counter: current_value,
       rate: state.previous_delta / 10
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
    {:noreply, %{state | previous_delta: pending_delta, pending_delta: 0}}
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
