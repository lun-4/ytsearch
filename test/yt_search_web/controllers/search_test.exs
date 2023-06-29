defmodule YtSearchWeb.SearchTest do
  use YtSearchWeb.ConnCase, async: false
  import Mock

  @channel_data "{\"_type\": \"url\", \"url\": \"https://www.youtube.com/channel/UCv3mh2P-q3UCtR9-2q8B-ZA\", \"id\": \"UCv3mh2P-q3UCtR9-2q8B-ZA\", \"ie_key\": \"YoutubeTab\", \"channel\": \"The Urban Rescue Ranch\", \"channel_id\": \"UCv3mh2P-q3UCtR9-2q8B-ZA\", \"channel_url\": \"https://www.youtube.com/channel/UCv3mh2P-q3UCtR9-2q8B-ZA\", \"title\": \"The Urban Rescue Ranch\", \"channel_follower_count\": null, \"thumbnails\": [{\"url\": \"//yt3.ggpht.com/EjQqWihI9-49mjhDiLd3OJ1ixeyaqEPdKXhDaCncg5R-0Ym1-mKw92MEeFO2QTsVgH2pYnfPGw=s88-c-k-c0x00ffffff-no-rj-mo\", \"height\": 88, \"width\": 88}, {\"url\": \"//yt3.ggpht.com/EjQqWihI9-49mjhDiLd3OJ1ixeyaqEPdKXhDaCncg5R-0Ym1-mKw92MEeFO2QTsVgH2pYnfPGw=s176-c-k-c0x00ffffff-no-rj-mo\", \"height\": 176, \"width\": 176}], \"playlist_count\": 2510000, \"description\": \"I have a tiny urban rescue ranch/homestead in central Texas. Join me as i create and manage the homestead and all of its\u00a0...\", \"__x_forwarded_for_ip\": null, \"webpage_url\": \"https://www.youtube.com/channel/UCv3mh2P-q3UCtR9-2q8B-ZA\", \"original_url\": \"https://www.youtube.com/channel/UCv3mh2P-q3UCtR9-2q8B-ZA\", \"webpage_url_basename\": \"UCv3mh2P-q3UCtR9-2q8B-ZA\", \"webpage_url_domain\": \"youtube.com\", \"extractor\": \"youtube:tab\", \"extractor_key\": \"YoutubeTab\", \"playlist\": \"urban rescue ranch\", \"playlist_id\": \"urban rescue ranch\", \"playlist_title\": \"urban rescue ranch\", \"playlist_uploader\": null, \"playlist_uploader_id\": null, \"n_entries\": 10, \"playlist_index\": 1, \"__last_playlist_index\": 10, \"playlist_autonumber\": 1, \"epoch\": 1687803719, \"filename\": \"The Urban Rescue Ranch [UCv3mh2P-q3UCtR9-2q8B-ZA].NA\", \"urls\": \"https://www.youtube.com/channel/UCv3mh2P-q3UCtR9-2q8B-ZA\", \"_version\": {\"version\": \"2023.03.04\", \"current_git_head\": null, \"release_git_head\": \"392389b7df7b818f794b231f14dc396d4875fbad\", \"repository\": \"yt-dlp/yt-dlp\"}}"
  @video_data "{\"_type\": \"url\", \"ie_key\": \"Youtube\", \"id\": \"Jouh2mdt1fI\", \"url\": \"https://www.youtube.com/watch?v=Jouh2mdt1fI\", \"title\": \"How to Cook Capybara Pie (eating Big Ounce)\", \"description\": null, \"duration\": 612.0, \"channel_id\": \"UCv3mh2P-q3UCtR9-2q8B-ZA\", \"channel\": \"The Urban Rescue Ranch\", \"channel_url\": \"https://www.youtube.com/channel/UCv3mh2P-q3UCtR9-2q8B-ZA\", \"thumbnails\": [{\"url\": \"https://i.ytimg.com/vi/Jouh2mdt1fI/hq720.jpg?sqp=-oaymwEcCOgCEMoBSFXyq4qpAw4IARUAAIhCGAFwAcABBg==&rs=AOn4CLAPEfEj6_EjWEq_78M77ogb3P8iEw\", \"height\": 202, \"width\": 360}, {\"url\": \"https://i.ytimg.com/vi/Jouh2mdt1fI/hq720.jpg?sqp=-oaymwEcCNAFEJQDSFXyq4qpAw4IARUAAIhCGAFwAcABBg==&rs=AOn4CLDmWrUVI_62g53kMu_yXalj63oOLA\", \"height\": 404, \"width\": 720}], \"timestamp\": null, \"release_timestamp\": null, \"availability\": null, \"view_count\": 1245513, \"live_status\": null, \"__x_forwarded_for_ip\": null, \"webpage_url\": \"https://www.youtube.com/watch?v=Jouh2mdt1fI\", \"original_url\": \"https://www.youtube.com/watch?v=Jouh2mdt1fI\", \"webpage_url_basename\": \"watch\", \"webpage_url_domain\": \"youtube.com\", \"extractor\": \"youtube\", \"extractor_key\": \"Youtube\", \"playlist_count\": null, \"playlist\": \"urban rescue ranch\", \"playlist_id\": \"urban rescue ranch\", \"playlist_title\": \"urban rescue ranch\", \"playlist_uploader\": null, \"playlist_uploader_id\": null, \"n_entries\": 10, \"playlist_index\": 2, \"__last_playlist_index\": 10, \"playlist_autonumber\": 2, \"duration_string\": \"10:12\", \"epoch\": 1687803719, \"filename\": \"How to Cook Capybara Pie (eating Big Ounce) [Jouh2mdt1fI].NA\", \"urls\": \"https://www.youtube.com/watch?v=Jouh2mdt1fI\", \"_version\": {\"version\": \"2023.03.04\", \"current_git_head\": null, \"release_git_head\": \"392389b7df7b818f794b231f14dc396d4875fbad\", \"repository\": \"yt-dlp/yt-dlp\"}}"
  @video_data_2 "{\"_type\": \"url\", \"ie_key\": \"Youtube\", \"id\": \"Jouh2mdt1fz\", \"url\": \"https://www.youtube.com/watch?v=Jouh2mdt1fI\", \"title\": \"How to Cook Capybara Pie (eating Big Ounce)\", \"description\": null, \"duration\": 612.0, \"channel_id\": \"UCv3mh2P-q3UCtR9-2q8B-ZA\", \"channel\": \"The Urban Rescue Ranch\", \"channel_url\": \"https://www.youtube.com/channel/UCv3mh2P-q3UCtR9-2q8B-ZA\", \"thumbnails\": [{\"url\": \"https://i.ytimg.com/vi/Jouh2mdt1fI/hq720.jpg?sqp=-oaymwEcCOgCEMoBSFXyq4qpAw4IARUAAIhCGAFwAcABBg==&rs=AOn4CLAPEfEj6_EjWEq_78M77ogb3P8iEw\", \"height\": 202, \"width\": 360}, {\"url\": \"https://i.ytimg.com/vi/Jouh2mdt1fI/hq720.jpg?sqp=-oaymwEcCNAFEJQDSFXyq4qpAw4IARUAAIhCGAFwAcABBg==&rs=AOn4CLDmWrUVI_62g53kMu_yXalj63oOLA\", \"height\": 404, \"width\": 720}], \"timestamp\": null, \"release_timestamp\": null, \"availability\": null, \"view_count\": 1245513, \"live_status\": null, \"__x_forwarded_for_ip\": null, \"webpage_url\": \"https://www.youtube.com/watch?v=Jouh2mdt1fI\", \"original_url\": \"https://www.youtube.com/watch?v=Jouh2mdt1fI\", \"webpage_url_basename\": \"watch\", \"webpage_url_domain\": \"youtube.com\", \"extractor\": \"youtube\", \"extractor_key\": \"Youtube\", \"playlist_count\": null, \"playlist\": \"urban rescue ranch\", \"playlist_id\": \"urban rescue ranch\", \"playlist_title\": \"urban rescue ranch\", \"playlist_uploader\": null, \"playlist_uploader_id\": null, \"n_entries\": 10, \"playlist_index\": 2, \"__last_playlist_index\": 10, \"playlist_autonumber\": 2, \"duration_string\": \"10:12\", \"epoch\": 1687803719, \"filename\": \"How to Cook Capybara Pie (eating Big Ounce) [Jouh2mdt1fI].NA\", \"urls\": \"https://www.youtube.com/watch?v=Jouh2mdt1fI\", \"_version\": {\"version\": \"2023.03.04\", \"current_git_head\": null, \"release_git_head\": \"392389b7df7b818f794b231f14dc396d4875fbad\", \"repository\": \"yt-dlp/yt-dlp\"}}"
  @test_output "#{@channel_data}\n#{@video_data}\n#{@video_data_2}"

  defp verify_single_result(given, expected) do
    given_without_slot_id =
      given
      |> Map.delete("slot_id")

    assert given_without_slot_id == expected
  end

  defp verify_search_results(json_response) do
    verify_single_result(json_response["search_results"] |> Enum.at(0), %{
      "duration" => 612.0,
      "title" => "How to Cook Capybara Pie (eating Big Ounce)",
      "youtube_id" => "Jouh2mdt1fI",
      "youtube_url" => "https://www.youtube.com/watch?v=Jouh2mdt1fI",
      "channel_name" => "The Urban Rescue Ranch",
      "description" => nil,
      "uploaded_at" => 1_687_803_719,
      "view_count" => 1_245_513
    })

    verify_single_result(
      json_response["search_results"] |> Enum.at(1),
      %{
        "duration" => 612.0,
        "title" => "How to Cook Capybara Pie (eating Big Ounce)",
        "youtube_id" => "Jouh2mdt1fz",
        "youtube_url" => "https://www.youtube.com/watch?v=Jouh2mdt1fI",
        "channel_name" => "The Urban Rescue Ranch",
        "description" => nil,
        "uploaded_at" => 1_687_803_719,
        "view_count" => 1_245_513
      }
    )

    assert json_response["slot_id"] == "1"
  end

  test "it does the thing", %{conn: conn} do
    with_mock(
      System,
      [:passthrough],
      cmd: fn _, _ ->
        {@test_output, 0}
      end
    ) do
      conn =
        conn
        |> get(~p"/api/v1/search?search=urban+rescue+ranch")

      resp_json = json_response(conn, 200)
      verify_search_results(resp_json)
      second_slot_id = resp_json["search_results"] |> Enum.at(1) |> Access.get("slot_id")

      conn =
        conn
        |> get("/api/v1/s/#{second_slot_id}")

      assert get_resp_header(conn, "location") == ["https://youtube.com/watch?v=Jouh2mdt1fz"]
    end
  end

  test "small route", %{conn: conn} do
    with_mock(
      System,
      [:passthrough],
      cmd: fn _, _ ->
        {@test_output, 0}
      end
    ) do
      conn =
        conn
        |> get(~p"/a/1/s?q=urban+rescue+ranch")

      assert verify_search_results(json_response(conn, 200))
    end
  end
end
