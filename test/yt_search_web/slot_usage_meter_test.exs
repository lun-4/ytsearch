defmodule YtSearchWeb.SlotUsageMeterTest do
  use YtSearchWeb.ConnCase, async: false
  alias YtSearch.Slot
  alias YtSearch.Repo
  import Ecto.Query

  alias YtSearch.SlotUtilities.UsageMeter

  @one_by_one_test_insert false

  setup do
    from(s in YtSearch.Slot, select: s)
    |> Repo.update_all(
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
      |> Repo.update_all(
        set: [
          video_duration: wanted_duration
        ]
      )

      [id_limit | acc]
    end)

    # 0..100_000
    []
    |> Enum.map(fn id ->
      duration =
        cond do
          id < 50000 -> 720
          id < 70000 -> 1800
          id < 90000 -> 3600
          true -> 7200
        end

      # TODO batch update
      %{
        id: id,
        youtube_id: random_yt_id(),
        video_duration: duration,
        inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
        updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
        inserted_at_v2: DateTime.to_unix(DateTime.utc_now())
      }
    end)
    |> Enum.shuffle()
    |> Enum.chunk_every(1500)
    |> Enum.each(fn batch ->
      IO.puts(
        "inserting #{length(batch)} slots (test setup) (#{inspect(batch |> Enum.at(0))}, #{inspect(batch |> Enum.at(-1))})"
      )

      if @one_by_one_test_insert do
        batch
        |> Enum.each(fn el ->
          Repo.insert(%Slot{
            id: el.id,
            youtube_id: el.youtube_id,
            video_duration: el.video_duration,
            inserted_at: el.inserted_at,
            updated_at: el.updated_at
          })
        end)
      else
        Repo.insert_all(Slot, batch)
      end
    end)

    IO.puts("done!")
  end

  defp random_yt_id do
    :rand.uniform(100_000_000_000_000) |> to_string |> Base.encode64()
  end

  defp time_travel_slots_to_expiration(duration) do
    # expiration_seconds = (4 * duration) |> trunc

    {count, updated_slots} =
      from(
        s in YtSearch.Slot,
        where: s.video_duration == ^duration,
        select: s.id
      )
      |> Repo.update_all(
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
    counters = UsageMeter.tick()
    IO.inspect(counters)
    assert Keyword.get(counters, Slot) == 100_000

    # now, if we set the slots with duration 720 to inserted_at_v2 - 720,
    # our countes should be around 50k
    time_travel_slots_to_expiration(720)
    counters = UsageMeter.tick()
    IO.inspect(counters)
    assert Keyword.get(counters, Slot) == 50_000

    time_travel_slots_to_expiration(1800)
    counters = UsageMeter.tick()
    IO.inspect(counters)
    assert Keyword.get(counters, Slot) == 30_000

    time_travel_slots_to_expiration(3600)
    counters = UsageMeter.tick()
    IO.inspect(counters)
    assert Keyword.get(counters, Slot) == 10_000

    time_travel_slots_to_expiration(7200)
    counters = UsageMeter.tick()
    IO.inspect(counters)
    assert Keyword.get(counters, Slot) == 0
  end
end
