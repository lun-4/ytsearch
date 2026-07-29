defmodule YtSearch.ThumbnailerClientTest do
  use YtSearch.DataCase, async: false

  alias YtSearch.ChannelSlot
  alias YtSearch.SearchSlot
  alias YtSearch.Slot
  alias YtSearch.ThumbnailerClient

  setup do
    Cachex.clear(:tabs)
    :ok
  end

  defp random_yt_id do
    :rand.uniform(100_000_000_000) |> Integer.to_string() |> Base.encode64()
  end

  defp sync_cache_key(slot) do
    "thumbnailer_sync:#{slot.id}:#{:erlang.phash2(slot.query)}"
  end

  test "gather_video_slots batches lookups, keeps entry order, drops missing" do
    slot1 = Slot.create(random_yt_id(), 3600)
    slot2 = Slot.create(random_yt_id(), 3600)
    missing_id = 199_999

    entries = [
      %{"type" => "video", "slot_id" => "#{slot2.id}"},
      %{"type" => "channel", "slot_id" => "12345"},
      %{"type" => "short", "slot_id" => "#{missing_id}"},
      %{"type" => "livestream", "slot_id" => "#{slot1.id}"}
    ]

    result = ThumbnailerClient.gather_video_slots(entries)

    assert Enum.map(result, & &1.id) == [slot2.id, slot1.id]
    assert Enum.map(result, & &1.youtube_id) == [slot2.youtube_id, slot1.youtube_id]
  end

  test "gather_channel_slots uniques ids and ignores entries without channel_slot" do
    channel = ChannelSlot.create(random_yt_id())

    entries = [
      %{"type" => "video", "channel_slot" => "#{channel.id}"},
      %{"type" => "video", "channel_slot" => "#{channel.id}"},
      %{"type" => "video", "channel_slot" => nil},
      %{"type" => "video"}
    ]

    result = ThumbnailerClient.gather_channel_slots(entries)

    assert Enum.map(result, & &1.id) == [channel.id]
  end

  test "gather functions handle empty entries" do
    assert ThumbnailerClient.gather_video_slots([]) == []
    assert ThumbnailerClient.gather_channel_slots([]) == []
  end

  describe "submit_search_slot throttling" do
    setup do
      System.put_env("EXTERNAL_THUMBNAIL_NODE", "http://127.0.0.1:1")
      on_exit(fn -> System.delete_env("EXTERNAL_THUMBNAIL_NODE") end)

      slot = %SearchSlot{
        id: 424_242,
        query: "ytsearch://throttle-test",
        slots_json: "[]",
        type: :fetched
      }

      {:ok, slot: slot}
    end

    test "throttle: true against an unreachable node errors and does not populate the cache",
         %{slot: slot} do
      # first attempt: no cache entry yet, so it actually tries the HTTP call
      # and fails against the unreachable node
      assert {:error, _} = ThumbnailerClient.submit_search_slot(slot, throttle: true)

      # a failed submit must NOT poison the throttle cache
      assert {:ok, nil} = Cachex.get(:tabs, sync_cache_key(slot))

      # so the next hit still attempts (and errors again) rather than skipping
      assert {:error, _} = ThumbnailerClient.submit_search_slot(slot, throttle: true)
    end

    test "throttle: true with a seeded cache key returns :ok without hitting HTTP",
         %{slot: slot} do
      # seed the throttle cache as if a prior sync succeeded
      Cachex.put(:tabs, sync_cache_key(slot), true)

      # even though the node is unreachable, the throttle short-circuits to :ok
      # without any HTTP attempt
      assert :ok = ThumbnailerClient.submit_search_slot(slot, throttle: true)
    end

    test "without throttle, an unreachable node always errors", %{slot: slot} do
      Cachex.put(:tabs, sync_cache_key(slot), true)
      # no throttle flag -> the seeded cache is ignored and the HTTP call is made
      assert {:error, _} = ThumbnailerClient.submit_search_slot(slot)
    end
  end
end
