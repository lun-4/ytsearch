defmodule YtSearch.SlotUtilities.UsageMeter do
  require Logger
  alias YtSearch.Repo
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
        count =
          case slot_type do
            YtSearch.Slot ->
              now = YtSearch.SlotUtilities.generate_unix_timestamp_integer()

              query =
                from s in slot_type,
                  where: fragment("unixepoch(?)", s.expires_at) > ^now,
                  select: count("*")

              Repo.one(query)

            _ ->
              expiry_time =
                NaiveDateTime.utc_now()
                |> NaiveDateTime.add(-slot_type.ttl)

              query =
                from s in slot_type,
                  where: s.inserted_at > ^expiry_time,
                  select: count("*")

              Repo.one(query)
          end

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
