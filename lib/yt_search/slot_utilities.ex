defmodule YtSearch.SlotUtilities do
  import Ecto.Query
  require Logger

  defp expiration_for(%{} = spec) do
    NaiveDateTime.utc_now()
    |> NaiveDateTime.add(spec.ttl)
    |> NaiveDateTime.truncate(:second)
  end

  def put_simple_expiration(params, module) do
    spec = module.slot_spec()

    params
    |> Map.put(:expires_at, expiration_for(spec))
  end

  def put_opts(params, opts) do
    params
    |> then(fn params ->
      keepalive = Keyword.get(opts, :keepalive)

      if keepalive != nil do
        params
        |> Map.put(:keepalive, keepalive)
      else
        params
      end
    end)
  end

  def put_used(params) do
    params
    |> Map.put(
      :used_at,
      NaiveDateTime.utc_now()
      |> NaiveDateTime.truncate(:second)
    )
  end

  def mark_used(%module{} = slot) do
    Logger.info("mark used #{inspect(module)} slot #{slot.id}")

    slot
    |> module.changeset(%{} |> put_used())
    |> repo(module).update!()
  end

  def min_time_between_refreshes do
    Application.get_env(:yt_search, YtSearch.Constants)[:minimum_time_between_refreshes] || 60
  end

  def refresh_expiration(%module{} = slot, opts \\ []) do
    if NaiveDateTime.diff(slot.used_at, NaiveDateTime.utc_now(), :second) <=
         -min_time_between_refreshes() do
      Logger.info("refresh expiration on #{inspect(module)} slot #{slot.id}")

      slot
      |> module.changeset(
        %{}
        |> put_simple_expiration(module)
        |> put_opts(opts)
        |> put_used()
      )
      |> repo(module).update!()
    else
      slot
    end
  end

  def generate_unix_timestamp do
    NaiveDateTime.utc_now()
    |> NaiveDateTime.truncate(:second)
  end

  def generate_unix_timestamp_integer do
    DateTime.to_unix(DateTime.utc_now())
  end

  def strict_ttl(nil), do: nil
  def strict_ttl(%{keepalive: true} = entity), do: entity

  def strict_ttl(entity) do
    now = generate_unix_timestamp()

    if NaiveDateTime.compare(entity.expires_at, now) == :gt do
      entity
    else
      nil
    end
  end

  def repo(YtSearch.Slot), do: YtSearch.Data.SlotRepo
  def repo(YtSearch.ChannelSlot), do: YtSearch.Data.ChannelSlotRepo
  def repo(YtSearch.PlaylistSlot), do: YtSearch.Data.PlaylistSlotRepo
  def repo(YtSearch.SearchSlot), do: YtSearch.Data.SearchSlotRepo
  def repo(YtSearch.Thumbnail), do: YtSearch.Data.ThumbnailRepo

  defmodule RecycledSlotAge do
    use Prometheus.Metric

    def setup() do
      Histogram.declare(
        name: :yts_recycle_slot_age,
        help: "age of slots when they're forcefully recycled back for reallocation",
        labels: [:type],
        buckets: [
          10,
          20,
          30,
          40,
          60,
          2 * 60,
          10 * 60,
          20 * 60,
          60 * 60,
          2 * 60 * 60,
          3 * 60 * 60,
          6 * 60 * 60,
          8 * 60 * 60,
          12 * 60 * 60
        ]
      )
    end

    def register(type, age) do
      Histogram.observe(
        [
          name: :yts_recycle_slot_age,
          labels: [type]
        ],
        age
      )
    end
  end

  def generate_id_v3(module) do
    now = generate_unix_timestamp_integer()

    from(s in module,
      where: fragment("unixepoch(?)", s.expires_at) < ^now and not s.keepalive,
      select: s,
      limit: 1
    )
    |> repo(module).replica().all()
    |> then(fn
      [] ->
        from(s in module,
          select: s,
          where: not s.keepalive,
          order_by: [
            asc: fragment("unixepoch(?)", s.used_at)
          ],
          limit: 5
        )
        |> repo(module).replica().all()
        |> then(fn slots ->
          slot_ids =
            slots
            |> Enum.map(fn slot ->
              age = NaiveDateTime.diff(slot.expires_at, generate_unix_timestamp(), :second)
              RecycledSlotAge.register(module, age)
              slot.id
            end)

          from(s in module,
            update: [set: [expires_at: ^~N[2020-01-01 00:00:00]]],
            where: s.id in ^slot_ids
          )
          |> repo(module).update_all([])

          slot_ids
        end)
        |> Enum.shuffle()
        |> Enum.at(0)
        |> then(fn
          nil ->
            raise "there are no N-oldest-used slots. this is an incorrect state"

          id ->
            {:ok, id}
        end)

      [expired_slot | _] ->
        {:ok, expired_slot.id}
    end)
  end
end
