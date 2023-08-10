defmodule YtSearch.ThumbnailAtlasTest do
  use YtSearchWeb.ConnCase, async: true

  alias YtSearch.Slot
  alias YtSearch.SearchSlot
  alias YtSearch.ChannelSlot
  alias YtSearch.Thumbnail

  defp png_data do
    File.read!("test/support/hq720.webp")
  end

  @test_youtube_id "YM3ZQF5Xbe8"

  setup do
    # setup
    thumb = Thumbnail.insert(@test_youtube_id, "image/webp", png_data())
    slot = Slot.create(@test_youtube_id, 3600)
    channel_slot = ChannelSlot.from(@test_youtube_id)

    search_slot =
      SearchSlot.from_playlist(
        [
          %{type: "video", slot_id: "#{slot.id}"},
          %{type: "channel", slot_id: "#{channel_slot.id}"}
        ],
        "youtube.com/test"
      )

    %{slot: slot, search_slot: search_slot, thumbnnail: thumb}
  end

  test "creates an atlas from a single thumbnail", %{conn: conn, search_slot: search_slot} do
    resp =
      conn
      |> get("/a/1/at/#{search_slot.id}")

    assert resp.status == 200
    assert Plug.Conn.get_resp_header(resp, "content-type") == ["image/png"]

    # have to dump data somewhere
    temporary_path = Temp.path!()
    File.write!(temporary_path, resp.resp_body)
    YtSearch.AssertUtil.image(temporary_path)
  end
end
