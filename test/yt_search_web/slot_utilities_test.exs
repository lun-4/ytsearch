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
end
