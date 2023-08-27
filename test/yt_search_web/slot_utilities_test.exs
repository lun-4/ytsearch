defmodule YtSearchWeb.SlotUtilitiesTest do
  use YtSearchWeb.ConnCase, async: false
  alias YtSearch.Slot
  alias YtSearch.Repo

  defp random_yt_id do
    :rand.uniform(100_000_000_000_000) |> to_string |> Base.encode64()
  end

  defp printtime(func) do
    prev = System.monotonic_time()
    func.()
    next = System.monotonic_time()
    diff = next - prev
    diff |> System.convert_time_unit(:native, :millisecond)

    IO.puts("took #{diff} ms running function")
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

      0..((unquote(slot_type).urls() * cutoff_point) |> trunc)
      |> Enum.shuffle()
      |> Enum.map(fn id ->
        case unquote(slot_type) do
          YtSearch.Slot ->
            %{
              id: id,
              youtube_id: random_yt_id(),
              inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
              updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
              inserted_at_v2: DateTime.to_unix(DateTime.utc_now())
            }

          YtSearch.SearchSlot ->
            %{
              id: id,
              slots_json: "[]",
              query: "amongnus",
              inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
              updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
            }

          s when s in [YtSearch.ChannelSlot, YtSearch.PlaylistSlot] ->
            %{
              id: id,
              youtube_id: random_yt_id(),
              inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
              updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
            }
        end
      end)
      |> Enum.chunk_every(5000)
      |> Enum.each(fn batch ->
        IO.puts("inserting #{length(batch)} slots (pre-test)")

        printtime(fn ->
          Repo.insert_all(unquote(slot_type), batch)
        end)
      end)

      # then see how things go on the second half (one by one id gen)

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

            YtSearch.SearchSlot ->
              slot_type.from_playlist([], random_yt_id())

            s when s in [YtSearch.ChannelSlot, YtSearch.PlaylistSlot] ->
              s.from(random_yt_id())
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
        inserted_at: slot.inserted_at |> NaiveDateTime.add(-(Slot.min_ttl() + 1), :second),
        inserted_at_v2: slot.inserted_at_v2 - Slot.min_ttl() + 1
      )
      |> YtSearch.Repo.update!()

    assert YtSearch.TTL.expired?(changed_slot)

    fetched_slot = YtSearch.Slot.fetch_by_id(slot.id)
    assert fetched_slot == nil

    same_slot = YtSearch.Slot.create(youtube_id, 1)
    assert same_slot.id == slot.id
    assert same_slot.inserted_at > changed_slot.inserted_at
    assert same_slot.inserted_at_v2 > changed_slot.inserted_at_v2
  end
end
