defmodule YtSearch.SlotUtilities.UsageMeter do
  use GenServer
  require Logger

  alias YtSearch.Repo

  import Ecto.Query

  def start_link(arg) do
    GenServer.start_link(__MODULE__, arg)
  end

  @slot_types [
    YtSearch.Slot,
    YtSearch.ChannelSlot,
    YtSearch.PlaylistSlot,
    YtSearch.SearchSlot
  ]

  defmodule Gauge do
    use Prometheus.Metric

    def setup() do
      Gauge.declare(
        name: :yts_slot_usage,
        help: "Amount of used slots for a given type",
        labels: [:type]
      )
    end

    def set(module, value) do
      Gauge.set([name: :yts_slot_usage, labels: [module]], value)
    end
  end

  @impl true
  def init(_arg) do
    schedule_work()
    {:ok, %{}}
  end

  def handle_info(:work, state) do
    do_calculate_counters()
    schedule_work()
    {:noreply, state}
  end

  defp do_calculate_counters() do
    Logger.debug("calculating slot usage...")

    @slot_types
    |> Enum.each(fn slot_type ->
      expiry_time =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-slot_type.ttl)

      query = from s in slot_type, where: s.inserted_at > ^expiry_time, select: count("*")
      result = Repo.one(query)
      Gauge.set(slot_type |> to_string |> String.split(".") |> Enum.at(-1), result)
    end)
  end

  defp schedule_work() do
    # every minute, with a jitter of -10..30s (to prevent a constant load on the server)
    # it's not really a problem to make this run every minute, but i am thinking webscale.
    next_tick =
      case Mix.env() do
        :prod -> 60 * 1000 + Enum.random((-10 * 1000)..(30 * 1000))
        _ -> 10000
      end

    Process.send_after(self(), :work, next_tick)
  end
end
