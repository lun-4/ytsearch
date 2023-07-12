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

  @tag timeout: :infinity
  @tag :skip
  test "it can still generate an id when a lot were already generated" do
    0..YtSearch.Slot.urls()
    |> Enum.chunk_every(100)
    |> Enum.each(fn batch ->
      batch
      |> Enum.map(fn num ->
        prev = System.monotonic_time()
        YtSearch.Slot.from(random_yt_id())
        next = System.monotonic_time()
        diff = next - prev
        ms = diff |> System.convert_time_unit(:native, :millisecond)

        if ms > 8 do
          IO.puts("#{ms}ms")
        end
      end)

      IO.puts("processed #{length(batch)} ids #{batch |> Enum.at(-1)}")
    end)

    # if it didnt error we gucci
  end

  test "it renews an existing expired slot" do
    youtube_id = random_yt_id()
    slot = Slot.from(youtube_id)

    changed_slot =
      slot
      |> Ecto.Changeset.change(
        inserted_at: slot.inserted_at |> NaiveDateTime.add(-100_000_000, :second)
      )
      |> YtSearch.Repo.update!()

    assert YtSearch.TTL.expired?(changed_slot, YtSearch.Slot.ttl())
    assert YtSearch.Slot.fetch_by_id(slot.id) == nil

    same_slot = YtSearch.Slot.from(youtube_id)
    assert same_slot.id == slot.id
    assert same_slot.inserted_at > changed_slot.inserted_at
  end
end
