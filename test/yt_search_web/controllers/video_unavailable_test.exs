defmodule YtSearchWeb.VideoUnavailableTest do
  use YtSearchWeb.ConnCase, async: false
  import Tesla.Mock
  alias YtSearch.Test.Data
  alias YtSearch.Slot
  alias YtSearch.ChannelSlot

  @test_youtube_id "DTDimRi2_TQ"
  @piped_video_output File.read!("test/support/piped_outputs/unavailable.json")
  @unavailable_channel_output File.read!("test/support/piped_outputs/unavailable_channel.json")
  @notfound_channel_output File.read!("test/support/piped_outputs/notfound_channel.json")

  @unavailable_channel_id "UCMsgXPD3wzzt8RxHJmXH7hQ"
  @notfound_channel_id "UCMsgXPD3wzzt8RxHJmXHHHH"

  setup do
    Data.default_global_mock(fn
      %{method: :get, url: "example.org/streams/#{@test_youtube_id}"} ->
        json(Jason.decode!(@piped_video_output), status: 500)

      %{method: :get, url: "example.org/channel/#{@unavailable_channel_id}"} ->
        json(Jason.decode!(@unavailable_channel_output), status: 500)

      %{method: :get, url: "example.org/channel/#{@notfound_channel_id}"} ->
        json(Jason.decode!(@notfound_channel_output), status: 500)
    end)

    %{
      slot: Slot.create(@test_youtube_id, 0),
      unavailable_channel_slot: ChannelSlot.from(@unavailable_channel_id),
      notfound_channel_slot: ChannelSlot.from(@notfound_channel_id)
    }
  end

  test "it successfully gives out 404 on unavailable video for subtitle", %{
    conn: conn,
    slot: slot
  } do
    conn =
      conn
      |> put_req_header("user-agent", "UnityWebRequest")
      |> get(~p"/a/2/sl/#{slot.id}")

    resp_json = json_response(conn, 200)
    assert resp_json["subtitle_data"] == nil
  end

  test "it successfully gives out 200 on unavailable video for mp4 link", %{
    conn: conn,
    slot: slot
  } do
    conn =
      conn
      |> get(~p"/a/2/sr/#{slot.id}")

    assert response_content_type(conn, :mp4)
    # idk how to assert video content
    assert response(conn, 200) != nil
  end

  test "it successfully gives out 404 on unavailable video for m3u8 link", %{
    conn: conn,
    slot: slot
  } do
    conn =
      conn
      |> get(~p"/a/2/sl/#{slot.id}/index.m3u8")

    assert text_response(conn, 404) == "error happened: E01"
  end

  test "it 404s on unavailable channels", %{conn: conn, unavailable_channel_slot: channel_slot} do
    conn =
      conn
      |> get(~p"/a/2/c/#{channel_slot.id}")

    assert json_response(conn, 404)["detail"] == "channel unavailable"
  end

  test "it 404s on non-existing channels", %{conn: conn, notfound_channel_slot: channel_slot} do
    conn =
      conn
      |> get(~p"/a/2/c/#{channel_slot.id}")

    assert json_response(conn, 404)["detail"] == "channel not found"
  end
end
