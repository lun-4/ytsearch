defmodule YtSearch.ThumbnailAtlasTest do
  use YtSearchWeb.ConnCase, async: false

  alias YtSearch.Slot
  alias YtSearch.SearchSlot
  alias YtSearch.ChannelSlot
  alias YtSearch.Thumbnail
  alias YtSearch.Test.Data

  @test_youtube_id "YM3ZQF5Xbe8"

  setup do
    # setup
    thumb = Thumbnail.insert(@test_youtube_id, "image/webp", Data.png(), [])
    slot = Slot.create(@test_youtube_id, 3600)
    channel_slot = ChannelSlot.create(@test_youtube_id)

    search_slot =
      SearchSlot.from_playlist(
        [
          %{type: "video", slot_id: "#{slot.id}", youtube_id: slot.youtube_id},
          %{type: "channel", slot_id: "#{channel_slot.id}", youtube_id: channel_slot.youtube_id}
        ],
        "youtube.com/test"
      )

    %{slot: slot, search_slot: search_slot, thumbnnail: thumb}
  end

  test "creates an atlas from a single thumbnail", %{conn: conn, search_slot: search_slot} do
    resp =
      conn
      |> get("/a/5/at/#{search_slot.id}")

    assert resp.status == 200
    assert Plug.Conn.get_resp_header(resp, "content-type") == ["image/png"]

    # have to dump data somewhere
    temporary_path = Temp.path!()
    File.write!(temporary_path, resp.resp_body)
    YtSearch.AssertUtil.image(temporary_path)
  end
end
