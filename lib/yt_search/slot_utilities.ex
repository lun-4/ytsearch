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
    if recently_used?(slot, generate_unix_timestamp()) do
      slot
    else
      Logger.info("mark used #{inspect(module)} slot #{slot.id}")

      slot
      |> module.changeset(%{} |> put_used())
      |> repo(module).update!()
    end
  end

  def min_time_between_refreshes do
    Application.get_env(:yt_search, YtSearch.Constants)[:minimum_time_between_refreshes] || 60
  end

  def recently_used?(slot, now) do
    slot.used_at != nil and
      NaiveDateTime.diff(now, slot.used_at, :second) < min_time_between_refreshes()
  end

  # a slot only counts as recently refreshed when its used_at is fresh AND
  # its remaining TTL is still near the maximum. the second clause matters
  # because mark_used bumps only used_at: without it, a near-expiry slot in
  # active use would never get its expiration extended
  def recently_refreshed?(%module{} = slot, now) do
    recently_used?(slot, now) and
      calc_seconds_until_expiry(slot, now) >=
        module.slot_spec().ttl - min_time_between_refreshes()
  end

  def refresh_expiration(%module{} = slot, opts \\ []) do
    keepalive = Keyword.get(opts, :keepalive)
    keepalive_changed? = keepalive != nil and keepalive != slot.keepalive

    if not keepalive_changed? and recently_refreshed?(slot, generate_unix_timestamp()) do
      slot
    else
      Logger.info("refresh expiration on #{inspect(module)} slot #{slot.id}")

      slot
      |> module.changeset(
        %{}
        |> put_simple_expiration(module)
        |> put_opts(opts)
        |> put_used()
      )
      |> repo(module).update!()
    end
  end

  @doc """
  Refresh expiration on many slots of the same module with a single UPDATE,
  skipping slots that were recently refreshed.
  """
  def refresh_expiration_bulk(module, slots) do
    now = generate_unix_timestamp()

    ids =
      slots
      |> Enum.reject(&recently_refreshed?(&1, now))
      |> Enum.map(fn slot -> slot.id end)
      |> Enum.uniq()

    if ids != [] do
      expires_at = expiration_for(module.slot_spec())

      # update_all bypasses changesets and does not auto-bump updated_at,
      # set it explicitly for parity with the changeset path
      from(s in module, where: s.id in ^ids)
      |> repo(module).update_all(set: [expires_at: expires_at, used_at: now, updated_at: now])
    end

    :ok
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
      Gauge.declare(
        name: :yts_expiration_delta_force_expiry,
        help:
          "when a slot is force-expired, how many seconds until a slot would've expired (HIGHER is WORSE)",
        labels: [:type]
      )

      Gauge.declare(
        name: :yts_used_at_delta_force_expiry,
        help:
          "when a slot is force-expired, how many seconds since a user has used the slot (LOWER is WORSE)",
        labels: [:type]
      )
    end

    def register_delta(:expires_at, type, delta) do
      Gauge.set(
        [
          name: :yts_expiration_delta_force_expiry,
          labels: [type]
        ],
        delta
      )
    end

    def register_delta(:used_at, type, delta) do
      Gauge.set(
        [
          name: :yts_used_at_delta_force_expiry,
          labels: [type]
        ],
        delta
      )
    end
  end

  def calc_seconds_until_expiry(slot, now) do
    NaiveDateTime.diff(slot.expires_at, now, :second)
  end

  def register_worst_by_field(module, now, slots, enum_fn, delta_fn, target) do
    slots
    |> Enum.map(fn slot ->
      {slot, delta_fn.(slot, now)}
    end)
    |> enum_fn.(fn {_slot, delta} -> delta end)
    |> then(fn {_slot, delta} ->
      Logger.debug(
        "register_worst_by_field #{inspect(target)} #{inspect(module)} #{inspect(delta)}"
      )

      RecycledSlotAge.register_delta(target, module, delta)
    end)
  end

  # `fragment("+?", s.id)` is used instead of bare s.id in the WHERE clauses below.
  #
  # this is done because doing "id < @max_ids" leads to a full table scan when that shouldn't
  # be done. the unixepoch() index is better for this case and a full table scan sucks, especially
  # for hot path like v3id
  #
  # turns out this is "documented" behavior by sqlite, though i assume that would break in
  # some version in 10 years or on sqlite4. who knows. more here:
  # https://sqlite.org/optoverview.html#disqualifying_where_clause_terms_using_unary_

  @doc """
  Find a reusable slot id for the given module.

  Must be called inside a `repo(module).transaction` (as the slot create
  functions do): candidate selection reads run on the primary so they
  participate in the caller's transaction. Reading from a replica here
  would allow two concurrent creates to select the same expired slot id.
  """
  def generate_id_v3(module) do
    now = generate_unix_timestamp_integer()
    max_ids = module.slot_spec().max_ids

    from(s in module,
      where:
        fragment("unixepoch(?)", s.expires_at) < ^now and not s.keepalive and
          fragment("+?", s.id) < ^max_ids,
      select: s,
      limit: 1
    )
    |> repo(module).all()
    |> then(fn
      [] ->
        Logger.debug("no expired slots, force expiring...")

        from(s in module,
          select: s,
          where: not s.keepalive and fragment("+?", s.id) < ^max_ids,
          order_by: [
            asc: fragment("unixepoch(?)", s.used_at)
          ],
          limit: 5
        )
        |> repo(module).all()
        |> then(fn slots ->
          now = generate_unix_timestamp()

          register_worst_by_field(
            module,
            now,
            slots,
            &Enum.max_by/2,
            fn slot, t ->
              NaiveDateTime.diff(slot.expires_at, t, :second)
            end,
            :expires_at
          )

          register_worst_by_field(
            module,
            now,
            slots,
            &Enum.min_by/2,
            fn slot, t ->
              NaiveDateTime.diff(t, slot.used_at, :second)
            end,
            :used_at
          )

          slot_ids =
            slots
            |> Enum.map(fn slot ->
              slot.id
            end)

          Logger.debug("force expiring #{inspect(slot_ids)}")

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
            Logger.debug("received force-expired slot #{id}")
            {:ok, id}
        end)

      [expired_slot | _] ->
        Logger.debug("received expired slot #{expired_slot.id}")
        {:ok, expired_slot.id}
    end)
  end
end
