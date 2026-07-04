defmodule YtSearch.ThumbnailerClientTest do
  use YtSearch.DataCase, async: false

  alias YtSearch.ChannelSlot
  alias YtSearch.Slot
  alias YtSearch.ThumbnailerClient

  defp random_yt_id do
    :rand.uniform(100_000_000_000) |> Integer.to_string() |> Base.encode64()
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
end
