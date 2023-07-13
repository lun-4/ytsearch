defmodule YtSearchWeb.SlotUsageMeterTest do
  use YtSearchWeb.ConnCase, async: true
  import Mock
  alias YtSearch.Slot
  alias YtSearch.Repo
  alias YtSearch.TTL
  import Ecto.Query

  alias YtSearch.SlotUtilities.UsageMeter

  @one_by_one_test_insert false

  setup do
    0..(YtSearch.Slot.urls() - 1)
    |> Enum.map(fn id ->
      duration =
        cond do
          id < 50000 -> 720
          id < 70000 -> 1800
          id < 90000 -> 3600
          true -> 7200
        end

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
            updated_at: el.updated_at,
            inserted_at_v2: el.inserted_at_v2
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
    expiration_seconds = (2.5 * duration) |> trunc

    {count, updated_slots} =
      from(
        s in YtSearch.Slot,
        where: s.video_duration == ^duration,
        select: s.id
      )
      |> Repo.update_all(
        inc: [inserted_at_v2: -expiration_seconds],
        set: [
          inserted_at:
            NaiveDateTime.local_now() |> NaiveDateTime.add(-expiration_seconds, :second)
        ]
      )

    IO.puts("updated #{count} slots")

    updated_slots
    |> Enum.each(fn slot_id ->
      assert Slot.fetch_by_id(slot_id) == nil
    end)
  end

  @tag :skip
  test "correctly gives slot count" do
    counters = UsageMeter.do_calculate_counters()
    IO.inspect(counters)
    assert Keyword.get(counters, Slot) == 100_000

    # now, if we set the slots with duration 720 to inserted_at_v2 - 720,
    # our countes should be around 50k
    time_travel_slots_to_expiration(720)
    counters = UsageMeter.do_calculate_counters()
    IO.inspect(counters)
    assert Keyword.get(counters, Slot) == 50_000

    time_travel_slots_to_expiration(1800)
    counters = UsageMeter.do_calculate_counters()
    IO.inspect(counters)
    assert Keyword.get(counters, Slot) == 30_000

    time_travel_slots_to_expiration(3600)
    counters = UsageMeter.do_calculate_counters()
    IO.inspect(counters)
    assert Keyword.get(counters, Slot) == 10_000

    time_travel_slots_to_expiration(7200)
    counters = UsageMeter.do_calculate_counters()
    IO.inspect(counters)
    assert Keyword.get(counters, Slot) == 0
  end
end
