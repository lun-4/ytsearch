defmodule YtSearch.SlotUtilities.UsageMeter do
  require Logger
  alias YtSearch.SlotUtilities
  import Ecto.Query

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

  @slot_types [
    YtSearch.Slot,
    YtSearch.ChannelSlot,
    YtSearch.PlaylistSlot,
    YtSearch.SearchSlot
  ]

  def tick() do
    Logger.debug("calculating slot usage...")

    counts =
      @slot_types
      |> Enum.map(fn slot_type ->
        now = SlotUtilities.generate_unix_timestamp_integer()

        count =
          from(s in slot_type,
            where: fragment("unixepoch(?)", s.expires_at) > ^now,
            select: count("*")
          )
          |> SlotUtilities.repo(slot_type).replica().one()

        {slot_type, count}
      end)

    counts
    |> Enum.each(fn {key, value} ->
      gauge_key = key |> to_string |> String.split(".") |> Enum.at(-1)
      Gauge.set(gauge_key, value)
    end)

    counts
  end
end
