defmodule YtSearchWeb.SlotUsageMeterTest do
  use YtSearchWeb.ConnCase, async: false
  alias YtSearch.Data.SlotRepo
  alias YtSearch.Slot
  import Ecto.Query

  alias YtSearch.SlotUtilities.UsageMeter

  setup do
    from(s in YtSearch.Slot, select: s)
    |> SlotRepo.update_all(
      set: [
        expires_at:
          NaiveDateTime.utc_now()
          |> NaiveDateTime.add(600, :second)
          |> NaiveDateTime.truncate(:second)
      ]
    )

    [
      {50000, 720},
      {70000, 1800},
      {90000, 3600},
      {100_000, 7200}
    ]
    |> Enum.reduce([], fn {id_limit, wanted_duration}, acc ->
      previous_id =
        case acc do
          [] -> 0
          [previous_id | _] -> previous_id
        end

      from(s in YtSearch.Slot, select: s, where: s.id >= ^previous_id and s.id < ^id_limit)
      |> SlotRepo.update_all(
        set: [
          video_duration: wanted_duration
        ]
      )

      [id_limit | acc]
    end)

    IO.puts("done!")
  end

  defp time_travel_slots_to_expiration(duration) do
    # expiration_seconds = (4 * duration) |> trunc

    {count, updated_slots} =
      from(
        s in YtSearch.Slot,
        where: s.video_duration == ^duration,
        select: s.id
      )
      |> SlotRepo.update_all(
        set: [
          expires_at: NaiveDateTime.utc_now() |> NaiveDateTime.add(-2, :second)
        ]
      )

    IO.puts("updated #{count} slots")

    updated_slots
    |> Enum.each(fn slot_id ->
      assert Slot.fetch_by_id(slot_id) == nil
    end)
  end

  @tag :slow
  test "correctly gives slot count" do
    # the setup gives duration markers to ids 0..100_000 only, the rest of
    # the (unexpired) pool stays counted throughout, so expectations are
    # relative to the full pool size instead of a hardcoded 100k pool
    pool_size = Slot.slot_spec().max_ids

    counters = UsageMeter.tick()
    IO.inspect(counters)
    assert Keyword.get(counters, Slot) == pool_size

    # now, if we set the slots with duration 720 to inserted_at_v2 - 720,
    # our counters should drop by those 50k
    time_travel_slots_to_expiration(720)
    counters = UsageMeter.tick()
    IO.inspect(counters)
    assert Keyword.get(counters, Slot) == pool_size - 50_000

    time_travel_slots_to_expiration(1800)
    counters = UsageMeter.tick()
    IO.inspect(counters)
    assert Keyword.get(counters, Slot) == pool_size - 70_000

    time_travel_slots_to_expiration(3600)
    counters = UsageMeter.tick()
    IO.inspect(counters)
    assert Keyword.get(counters, Slot) == pool_size - 90_000

    time_travel_slots_to_expiration(7200)
    counters = UsageMeter.tick()
    IO.inspect(counters)
    assert Keyword.get(counters, Slot) == pool_size - 100_000
  end

  @tag :slow
  test "counts expired keepalive slots" do
    from(s in YtSearch.Slot, select: s)
    |> SlotRepo.update_all(
      set: [
        expires_at:
          NaiveDateTime.utc_now()
          |> NaiveDateTime.add(-600, :second)
          |> NaiveDateTime.truncate(:second),
        keepalive: false
      ]
    )

    from(s in YtSearch.Slot, select: s, where: s.id < 100)
    |> SlotRepo.update_all(set: [keepalive: true])

    counters = UsageMeter.tick()
    assert Keyword.get(counters, Slot) == 100
  end
end
