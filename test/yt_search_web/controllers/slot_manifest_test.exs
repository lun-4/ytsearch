defmodule YtSearchWeb.SlotManifestTest do
  # Not async because we're modifying application config
  use YtSearchWeb.ConnCase, async: false

  alias YtSearch.Mp4Link
  import YtSearch.Factory.Slot

  describe "slot controller manifest serving" do
    test "serves regular video URL when prefer_fake_manifests is false", %{conn: conn} do
      # Create slot and link with manifest content
      youtube_id = "test_video_regular_#{System.unique_integer([:positive])}"
      slot_id = System.unique_integer([:positive, :monotonic]) + :rand.uniform(1_000_000)
      slot = insert(:slot, id: slot_id, youtube_id: youtube_id)

      manifest_content = """
      #EXTM3U
      #EXT-X-VERSION:6
      # Test manifest
      video.m3u8
      """

      Mp4Link.insert(
        youtube_id,
        "https://googlevideo.com/regular_video.mp4",
        nil,
        %{"quality" => "720p"},
        manifest_content
      )

      # Set config to false
      Application.put_env(
        :yt_search,
        YtSearch.Constants,
        Application.get_env(:yt_search, YtSearch.Constants)
        |> Keyword.put(:prefer_fake_manifests?, false)
      )

      # Request should redirect to regular video URL
      conn = get(conn, ~p"/api/v6/sr/#{slot.id}")
      assert redirected_to(conn) =~ "googlevideo.com/regular_video.mp4"
    end

    test "serves HLS manifest when prefer_fake_manifests is true", %{conn: conn} do
      # Create slot and link with manifest content  
      youtube_id = "test_video_manifest_#{System.unique_integer([:positive])}"
      slot_id = System.unique_integer([:positive, :monotonic]) + :rand.uniform(1_000_000)
      slot = insert(:slot, id: slot_id, youtube_id: youtube_id)

      manifest_content = """
      #EXTM3U
      #EXT-X-VERSION:6

      # Audio-only variant
      #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="Audio",DEFAULT=YES,AUTOSELECT=YES,URI="audio.m3u8"

      # Video variant with audio
      #EXT-X-STREAM-INF:BANDWIDTH=1128000,RESOLUTION=1280x720,CODECS="avc1.4d4020,mp4a.40.2",AUDIO="audio"
      video.m3u8
      """

      Mp4Link.insert(
        youtube_id,
        "https://googlevideo.com/regular_video.mp4",
        nil,
        %{"quality" => "720p"},
        manifest_content
      )

      # Set config to true
      Application.put_env(
        :yt_search,
        YtSearch.Constants,
        Application.get_env(:yt_search, YtSearch.Constants)
        |> Keyword.put(:prefer_fake_manifests?, true)
      )

      # Request should return manifest content
      conn = get(conn, ~p"/api/v6/sr/#{slot.id}")
      assert conn.status == 200

      assert get_resp_header(conn, "content-type") == [
               "application/vnd.apple.mpegurl; charset=utf-8"
             ]

      assert String.contains?(conn.resp_body, "#EXTM3U")
      assert String.contains?(conn.resp_body, "#EXT-X-VERSION:6")
      assert String.contains?(conn.resp_body, "video.m3u8")
      assert String.trim(conn.resp_body) == String.trim(manifest_content)
    end

    test "falls back to regular URL when manifest content is nil", %{conn: conn} do
      # Create a slot/link without manifest content
      youtube_id = "test_video_no_manifest_#{System.unique_integer([:positive])}"
      slot_id = System.unique_integer([:positive, :monotonic]) + :rand.uniform(1_000_000)
      slot = insert(:slot, id: slot_id, youtube_id: youtube_id)

      Mp4Link.insert(
        youtube_id,
        "https://googlevideo.com/fallback_video.mp4",
        nil,
        %{"quality" => "360p"},
        # No manifest content
        nil
      )

      # Set config to true
      Application.put_env(
        :yt_search,
        YtSearch.Constants,
        Application.get_env(:yt_search, YtSearch.Constants)
        |> Keyword.put(:prefer_fake_manifests?, true)
      )

      # Should still redirect to regular URL since no manifest content available
      conn = get(conn, ~p"/api/v6/sr/#{slot.id}")
      assert redirected_to(conn) =~ "googlevideo.com/fallback_video.mp4"
    end
  end
end
