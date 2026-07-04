defmodule YtSearchWeb.SlotUtilitiesTest do
  alias YtSearch.SlotUtilities
  alias YtSearch.Data.SlotRepo
  use YtSearchWeb.ConnCase, async: false
  alias YtSearch.Slot
  import Ecto.Query

  defp random_yt_id do
    :rand.uniform(100_000_000_000_000) |> to_string |> Base.encode64()
  end

  @slot_types [
    YtSearch.Slot,
    YtSearch.SearchSlot,
    YtSearch.ChannelSlot,
    YtSearch.PlaylistSlot
  ]

  @slot_types
  |> Enum.each(fn slot_type ->
    @tag :slow
    test "it can still generate an id when a lot were already generated #{inspect(slot_type)}" do
      cutoff_point =
        unless System.get_env("HARD_TIME") != nil do
          0.995
        else
          0.8
        end

      # load a bunch of slots to test with

      slot_module = unquote(slot_type)

      from(s in slot_module, select: s)
      |> SlotUtilities.repo(slot_module).update_all(
        set: [
          expires_at:
            NaiveDateTime.utc_now()
            |> NaiveDateTime.add(600, :second)
            |> NaiveDateTime.truncate(:second),
          used_at:
            NaiveDateTime.utc_now()
            |> NaiveDateTime.truncate(:second),
          keepalive: false
        ]
      )

      harder_test(unquote(slot_type), cutoff_point)

      # if it didnt error we gucci
    end
  end)

  defp harder_test(slot_type, cutoff_point) do
    ((slot_type.urls() * cutoff_point) |> trunc)..slot_type.urls()
    |> Enum.chunk_every(100)
    |> Enum.each(fn batch ->
      timings =
        batch
        |> Enum.map(fn _ ->
          prev = System.monotonic_time()

          case slot_type do
            YtSearch.Slot ->
              slot_type.create(random_yt_id(), 3600)

            YtSearch.ChannelSlot ->
              slot_type.create(random_yt_id())

            YtSearch.SearchSlot ->
              slot_type.from_playlist([], random_yt_id())

            YtSearch.PlaylistSlot ->
              YtSearch.PlaylistSlot.create(random_yt_id())
          end

          next = System.monotonic_time()
          diff = next - prev
          diff |> System.convert_time_unit(:native, :millisecond)
        end)

      max_timing = Enum.max(timings)
      min_timing = Enum.min(timings)
      sum_timings = Enum.reduce(timings, 0, fn x, acc -> x + acc end)
      avg_timing = sum_timings / length(timings)

      samples = timings |> Enum.shuffle() |> Enum.slice(0, 10)

      IO.puts("processed #{length(batch)} (finished at id #{batch |> Enum.at(-1)})")

      IO.puts(
        "\tmin:#{min_timing}ms avg:#{avg_timing}ms max:#{max_timing}ms sum:#{sum_timings}ms (#{inspect(samples)})"
      )

      assert sum_timings < 500
    end)
  end

  test "it renews an existing expired slot" do
    youtube_id = random_yt_id()
    slot = Slot.create(youtube_id, 1)

    changed_slot =
      slot
      |> Ecto.Changeset.change(
        expires_at:
          NaiveDateTime.utc_now()
          |> NaiveDateTime.add(-1, :second)
          |> NaiveDateTime.truncate(:second)
      )
      |> SlotRepo.update!()

    fetched_slot = YtSearch.Slot.fetch_by_id(slot.id)
    assert fetched_slot == nil

    same_slot = YtSearch.Slot.create(youtube_id, 1)
    assert same_slot.id == slot.id
    assert same_slot.expires_at > changed_slot.expires_at
  end

  test "it skips refresh writes within the minimum refresh window" do
    slot = Slot.create(random_yt_id(), 3600)

    # freshly created slot: recently used with a near-full TTL, so both
    # refresh paths must be write-free no-ops
    refreshed = SlotUtilities.refresh_expiration(slot)
    assert refreshed.used_at == slot.used_at
    assert refreshed.expires_at == slot.expires_at

    marked = SlotUtilities.mark_used(slot)
    assert marked.used_at == slot.used_at

    in_db = SlotRepo.get(Slot, slot.id)
    assert in_db.used_at == slot.used_at
    assert in_db.expires_at == slot.expires_at

    # a keepalive change forces the write even within the window
    kept = SlotUtilities.refresh_expiration(slot, keepalive: true)
    assert kept.keepalive == true
  end

  test "it refreshes a recently-used slot that is close to expiry" do
    slot = Slot.create(random_yt_id(), 3600)

    near_expiry =
      SlotUtilities.generate_unix_timestamp()
      |> NaiveDateTime.add(30, :second)

    slot =
      slot
      |> Ecto.Changeset.change(expires_at: near_expiry)
      |> SlotRepo.update!()

    # used_at is fresh but the remaining TTL is nearly gone: the
    # used_at-only gate must not starve the expiration bump
    refreshed = SlotUtilities.refresh_expiration(slot)
    assert NaiveDateTime.compare(refreshed.expires_at, near_expiry) == :gt
  end

  test "refresh_expiration_bulk refreshes stale slots and skips fresh ones" do
    past =
      SlotUtilities.generate_unix_timestamp()
      |> NaiveDateTime.add(-3600, :second)

    stale_slot =
      Slot.create(random_yt_id(), 3600)
      |> Ecto.Changeset.change(used_at: past, expires_at: past)
      |> SlotRepo.update!()

    fresh_slot = Slot.create(random_yt_id(), 3600)

    SlotUtilities.refresh_expiration_bulk(Slot, [stale_slot, fresh_slot])

    reloaded_stale = SlotRepo.get(Slot, stale_slot.id)
    assert NaiveDateTime.compare(reloaded_stale.expires_at, stale_slot.expires_at) == :gt
    assert NaiveDateTime.compare(reloaded_stale.used_at, stale_slot.used_at) == :gt

    reloaded_fresh = SlotRepo.get(Slot, fresh_slot.id)
    assert reloaded_fresh.expires_at == fresh_slot.expires_at
    assert reloaded_fresh.used_at == fresh_slot.used_at
  end

  test "it correctly expires the oldest-used slot" do
    # setup by writing all of em

    future =
      YtSearch.SlotUtilities.generate_unix_timestamp()
      |> NaiveDateTime.add(66666, :second)

    past =
      YtSearch.SlotUtilities.generate_unix_timestamp()
      |> NaiveDateTime.add(-99999, :second)

    from(s in YtSearch.Slot, select: s)
    |> YtSearch.Data.SlotRepo.update_all(
      set: [
        expires_at: future,
        used_at: past,
        video_duration: 60,
        inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
        updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
        keepalive: false
      ]
    )

    YtSearch.Slot.fetch_by_id(666)
    |> Ecto.Changeset.change(%{
      # even greater past
      expires_at: future |> NaiveDateTime.add(100_000, :day),
      used_at: past |> NaiveDateTime.add(-100_000, :minute)
    })
    |> YtSearch.Data.SlotRepo.update!()

    slot = YtSearch.Slot.fetch_by_id(666)
    assert slot != nil
    # it should force-expire 666 due to used_at being set in the very far past
    YtSearch.SlotUtilities.generate_id_v3(YtSearch.Slot)
    slot = YtSearch.Slot.fetch_by_id(666)
    assert slot == nil

    assert Prometheus.Metric.Gauge.value(
             name: :yts_expiration_delta_force_expiry,
             labels: [YtSearch.Slot]
           ) > 99900

    assert Prometheus.Metric.Gauge.value(
             name: :yts_used_at_delta_force_expiry,
             labels: [YtSearch.Slot]
           ) > 99900

    assert Prometheus.Metric.Gauge.value(
             name: :yts_used_at_delta_force_expiry,
             labels: [YtSearch.Slot]
           ) < 1_000_000
  end
end
