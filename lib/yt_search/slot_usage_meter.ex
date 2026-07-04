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

      Gauge.declare(
        name: :yts_slot_utilization_rate,
        help: "Utilization rate of slots for a given type",
        labels: [:type]
      )
    end

    def set(module, value) do
      Gauge.set([name: :yts_slot_usage, labels: [module]], value)
    end

    def set_rate(module, value) do
      Gauge.set([name: :yts_slot_utilization_rate, labels: [module]], value)
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
        replica = SlotUtilities.repo(slot_type).replica()

        # split the `unexpired OR keepalive` count into two disjoint
        # index-friendly counts: the OR would force a full-table scan,
        # while these hit the unixepoch(expires_at) expression index and
        # the partial keepalive index respectively
        unexpired =
          from(s in slot_type,
            where: fragment("unixepoch(?)", s.expires_at) > ^now,
            select: count("*")
          )
          |> replica.one()

        expired_keepalive =
          from(s in slot_type,
            where: s.keepalive and fragment("unixepoch(?)", s.expires_at) <= ^now,
            select: count("*")
          )
          |> replica.one()

        {slot_type, unexpired + expired_keepalive}
      end)

    counts
    |> Enum.each(fn {key, value} ->
      gauge_key = key |> to_string |> String.split(".") |> Enum.at(-1)
      Gauge.set(gauge_key, value)
      utilization_rate = (value / key.slot_spec().max_ids * 100) |> trunc
      Gauge.set_rate(gauge_key, utilization_rate)
    end)

    counts
  end
end
