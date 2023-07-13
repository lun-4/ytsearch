defmodule YtSearchWeb.SlotUtilitiesTest do
  use YtSearchWeb.ConnCase, async: true
  import Mock
  alias YtSearch.Slot
  alias YtSearch.Subtitle
  alias YtSearch.Repo
  import Ecto.Query

  defp random_yt_id do
    :rand.uniform(100_000_000_000_000) |> to_string |> Base.encode64()
  end

  defp printtime(func, print \\ false) do
    prev = System.monotonic_time()
    res = func.()
    next = System.monotonic_time()
    diff = next - prev
    diff |> System.convert_time_unit(:native, :millisecond)

    if print do
      IO.puts("took #{diff} ms running function")
    end
  end

  @tag timeout: :infinity
  @tag :skip
  test "it can still generate an id when a lot were already generated" do
    cutoff_point = 0.9

    # load a bunch of slots to test with

    0..((YtSearch.Slot.urls() * cutoff_point) |> trunc)
    |> Enum.shuffle()
    |> Enum.map(fn id ->
      %{
        id: id,
        youtube_id: random_yt_id(),
        inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
        updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
        inserted_at_v2: DateTime.to_unix(DateTime.utc_now())
      }
    end)
    |> Enum.chunk_every(2000)
    |> Enum.each(fn batch ->
      IO.puts("inserting #{length(batch)} slots (pre-test)")

      printtime(
        fn ->
          Repo.insert_all(YtSearch.Slot, batch)
        end,
        true
      )
    end)

    # then see how things go on the second half (one by one id gen)

    harder_test(cutoff_point)

    # if it didnt error we gucci
  end

  defp harder_test(cutoff_point) do
    ((YtSearch.Slot.urls() * cutoff_point) |> trunc)..YtSearch.Slot.urls()
    |> Enum.chunk_every(100)
    |> Enum.each(fn batch ->
      timings =
        batch
        |> Enum.map(fn num ->
          prev = System.monotonic_time()

          YtSearch.Slot.from(random_yt_id())

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
    end)
  end

  test "it renews an existing expired slot" do
    youtube_id = random_yt_id()
    slot = Slot.create(youtube_id, 1)

    changed_slot =
      slot
      |> Ecto.Changeset.change(
        inserted_at: slot.inserted_at |> NaiveDateTime.add(-(Slot.min_ttl() + 1), :second),
        inserted_at_v2: slot.inserted_at_v2 - Slot.min_ttl() + 1
      )
      |> YtSearch.Repo.update!()

    assert YtSearch.TTL.expired_video?(changed_slot, YtSearch.Slot)

    fetched_slot = YtSearch.Slot.fetch_by_id(slot.id)
    assert fetched_slot == nil

    same_slot = YtSearch.Slot.create(youtube_id, 1)
    assert same_slot.id == slot.id
    assert same_slot.inserted_at > changed_slot.inserted_at
    assert same_slot.inserted_at_v2 > changed_slot.inserted_at_v2
  end
end
