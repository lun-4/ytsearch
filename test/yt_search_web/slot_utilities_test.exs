defmodule YtSearchWeb.SlotUtilitiesTest do
  use YtSearchWeb.ConnCase, async: false
  alias YtSearch.Slot
  alias YtSearch.Repo
  import Ecto.Query

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

      case unquote(slot_type) do
        slot_module when slot_module in [YtSearch.Slot, YtSearch.ChannelSlot] ->
          from(s in slot_module, select: s)
          |> Repo.update_all(
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

        _ ->
          :ok
      end

      0..((unquote(slot_type).urls() * cutoff_point) |> trunc)
      |> Enum.shuffle()
      |> Enum.map(fn id ->
        case unquote(slot_type) do
          YtSearch.Slot ->
            nil

          YtSearch.ChannelSlot ->
            nil

          # %{
          #  id: id,
          #  youtube_id: random_yt_id(),
          #  inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
          #  updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
          # }

          YtSearch.SearchSlot ->
            %{
              id: id,
              slots_json: "[]",
              query: "amongnus",
              inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
              updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
            }

          YtSearch.PlaylistSlot ->
            %{
              id: id,
              youtube_id: random_yt_id(),
              inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
              updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
            }
        end
      end)
      |> Enum.filter(fn v -> v != nil end)
      |> Enum.chunk_every(1000)
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

            YtSearch.ChannelSlot ->
              slot_type.create(random_yt_id())

            YtSearch.SearchSlot ->
              slot_type.from_playlist([], random_yt_id())

            YtSearch.PlaylistSlot ->
              YtSearch.PlaylistSlot.from(random_yt_id())
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
      |> YtSearch.Repo.update!()

    fetched_slot = YtSearch.Slot.fetch_by_id(slot.id)
    assert fetched_slot == nil

    same_slot = YtSearch.Slot.create(youtube_id, 1)
    assert same_slot.id == slot.id
    assert same_slot.expires_at > changed_slot.expires_at
  end
end
