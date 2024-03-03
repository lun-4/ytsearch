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
  @music_premium_output File.read!("test/support/piped_outputs/music_premium_video.json")

  @upcoming_video_json File.read!("test/support/piped_outputs/upcoming_video.json")
  @upcoming_livestream_json File.read!("test/support/piped_outputs/upcoming_livestream.json")

  @unavailable_channel_id "UCMsgXPD3wzzt8RxHJmXH7hQ"
  @notfound_channel_id "UCMsgXPD3wzzt8RxHJmXHHHH"
  @music_premium_id "dlpKSIvHKKM"
  @no_subtitles_id "4trwogriouregjkl"
  @upcoming_video_id "8t7q628947"
  @upcoming_livestream_id "AAADKSJFKL38"

  setup do
    Data.default_global_mock(fn
      %{method: :get, url: "example.org/streams/#{@test_youtube_id}"} ->
        json(Jason.decode!(@piped_video_output), status: 500)

      %{method: :get, url: "example.org/streams/#{@music_premium_id}"} ->
        json(Jason.decode!(@music_premium_output), status: 500)

      %{method: :get, url: "example.org/streams/#{@no_subtitles_id}"} ->
        json(%{"subtitles" => []})

      %{method: :get, url: "example.org/channel/#{@unavailable_channel_id}"} ->
        json(Jason.decode!(@unavailable_channel_output), status: 500)

      %{method: :get, url: "example.org/channel/#{@notfound_channel_id}"} ->
        json(Jason.decode!(@notfound_channel_output), status: 500)

      %{method: :get, url: "example.org/streams/#{@upcoming_video_id}"} ->
        json(Jason.decode!(@upcoming_video_json), status: 500)

      %{method: :get, url: "example.org/streams/#{@upcoming_livestream_id}"} ->
        json(Jason.decode!(@upcoming_livestream_json), status: 500)

      %{method: :get, url: "sb.example.org/api/skipSegments?videoID=#{@no_subtitles_id}" <> _rest} ->
        json([])
    end)

    %{
      slot: Slot.create(@test_youtube_id, 0),
      music_premium_slot: Slot.create(@music_premium_id, 0),
      no_subtitles_slot: Slot.create(@no_subtitles_id, 0),
      unavailable_channel_slot: ChannelSlot.create(@unavailable_channel_id),
      notfound_channel_slot: ChannelSlot.create(@notfound_channel_id),
      upcoming_livestream_slot: Slot.create(@upcoming_livestream_id, 0),
      upcoming_video_slot: Slot.create(@upcoming_video_id, 0)
    }
  end

  test "it successfully gives out 404 on unavailable video for subtitle", %{
    conn: conn,
    slot: slot
  } do
    conn =
      conn
      |> put_req_header("user-agent", "UnityWebRequest")
      |> get(~p"/a/5/sr/#{slot.id}")

    resp_json = json_response(conn, 200)
    assert resp_json["subtitle_data"] == nil
  end

  test "it successfully gives out nil on no subtitles found", %{
    no_subtitles_slot: slot
  } do
    1..10
    |> Enum.map(fn _ ->
      Task.async(fn ->
        Phoenix.ConnTest.build_conn()
        |> put_req_header("user-agent", "UnityWebRequest")
        |> get(~p"/a/5/sr/#{slot.id}")
      end)
    end)
    |> Enum.map(fn task ->
      conn = Task.await(task)

      resp_json = json_response(conn, 200)
      assert resp_json["subtitle_data"] == nil
    end)

    resp_json =
      Phoenix.ConnTest.build_conn()
      |> put_req_header("user-agent", "UnityWebRequest")
      |> get(~p"/a/5/sr/#{slot.id}")
      |> json_response(200)

    assert resp_json["subtitle_data"] == nil
  end

  test "it successfully gives out 200 on unavailable video for mp4 link", %{
    conn: conn,
    slot: slot
  } do
    conn =
      conn
      |> get(~p"/a/5/sr/#{slot.id}")

    assert response_content_type(conn, :mp4)
    assert response(conn, 200) != nil
    assert get_resp_header(conn, "yts-failure-code") == ["E01"]
  end

  test "it successfully gives out 200 on unavailable video for mp4 link on music premium video",
       %{
         conn: conn,
         music_premium_slot: slot
       } do
    conn =
      conn
      |> get(~p"/a/5/sr/#{slot.id}")

    assert response_content_type(conn, :mp4)
    assert response(conn, 200) != nil
    assert get_resp_header(conn, "yts-failure-code") == ["E03"]
  end

  test "it 404s on unavailable channels", %{conn: conn, unavailable_channel_slot: channel_slot} do
    conn =
      conn
      |> get(~p"/a/5/c/#{channel_slot.id}")

    assert json_response(conn, 404)["detail"] == "channel unavailable"
  end

  test "it 404s on non-existing channels", %{conn: conn, notfound_channel_slot: channel_slot} do
    conn =
      conn
      |> get(~p"/a/5/c/#{channel_slot.id}")

    assert json_response(conn, 404)["detail"] == "channel not found"
  end

  test "it successfully gives out 200 on upcoming video",
       %{
         conn: conn,
         upcoming_video_slot: slot
       } do
    conn =
      conn
      |> get(~p"/a/5/sr/#{slot.id}")

    assert response_content_type(conn, :mp4)
    assert response(conn, 200) != nil
    assert get_resp_header(conn, "yts-failure-code") == ["E01"]
  end
end
