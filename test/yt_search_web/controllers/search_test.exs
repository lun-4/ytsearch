defmodule YtSearchWeb.SearchTest do
  use YtSearchWeb.ConnCase, async: false
  import Mock

  @channel_data "{\"_type\": \"url\", \"url\": \"https://www.youtube.com/channel/UCv3mh2P-q3UCtR9-2q8B-ZA\", \"id\": \"UCv3mh2P-q3UCtR9-2q8B-ZA\", \"ie_key\": \"YoutubeTab\", \"channel\": \"The Urban Rescue Ranch\", \"channel_id\": \"UCv3mh2P-q3UCtR9-2q8B-ZA\", \"channel_url\": \"https://www.youtube.com/channel/UCv3mh2P-q3UCtR9-2q8B-ZA\", \"title\": \"The Urban Rescue Ranch\", \"channel_follower_count\": null, \"thumbnails\": [{\"url\": \"//yt3.ggpht.com/EjQqWihI9-49mjhDiLd3OJ1ixeyaqEPdKXhDaCncg5R-0Ym1-mKw92MEeFO2QTsVgH2pYnfPGw=s88-c-k-c0x00ffffff-no-rj-mo\", \"height\": 88, \"width\": 88}, {\"url\": \"//yt3.ggpht.com/EjQqWihI9-49mjhDiLd3OJ1ixeyaqEPdKXhDaCncg5R-0Ym1-mKw92MEeFO2QTsVgH2pYnfPGw=s176-c-k-c0x00ffffff-no-rj-mo\", \"height\": 176, \"width\": 176}], \"playlist_count\": 2510000, \"description\": \"I have a tiny urban rescue ranch/homestead in central Texas. Join me as i create and manage the homestead and all of its\u00a0...\", \"__x_forwarded_for_ip\": null, \"webpage_url\": \"https://www.youtube.com/channel/UCv3mh2P-q3UCtR9-2q8B-ZA\", \"original_url\": \"https://www.youtube.com/channel/UCv3mh2P-q3UCtR9-2q8B-ZA\", \"webpage_url_basename\": \"UCv3mh2P-q3UCtR9-2q8B-ZA\", \"webpage_url_domain\": \"youtube.com\", \"extractor\": \"youtube:tab\", \"extractor_key\": \"YoutubeTab\", \"playlist\": \"urban rescue ranch\", \"playlist_id\": \"urban rescue ranch\", \"playlist_title\": \"urban rescue ranch\", \"playlist_uploader\": null, \"playlist_uploader_id\": null, \"n_entries\": 10, \"playlist_index\": 1, \"__last_playlist_index\": 10, \"playlist_autonumber\": 1, \"epoch\": 1687803719, \"filename\": \"The Urban Rescue Ranch [UCv3mh2P-q3UCtR9-2q8B-ZA].NA\", \"urls\": \"https://www.youtube.com/channel/UCv3mh2P-q3UCtR9-2q8B-ZA\", \"_version\": {\"version\": \"2023.03.04\", \"current_git_head\": null, \"release_git_head\": \"392389b7df7b818f794b231f14dc396d4875fbad\", \"repository\": \"yt-dlp/yt-dlp\"}}"
  @video_data "{\"_type\": \"url\", \"ie_key\": \"Youtube\", \"id\": \"Jouh2mdt1fI\", \"url\": \"https://www.youtube.com/watch?v=Jouh2mdt1fI\", \"title\": \"How to Cook Capybara Pie (eating Big Ounce)\", \"description\": null, \"duration\": 612.0, \"channel_id\": \"UCv3mh2P-q3UCtR9-2q8B-ZA\", \"channel\": \"The Urban Rescue Ranch\", \"channel_url\": \"https://www.youtube.com/channel/UCv3mh2P-q3UCtR9-2q8B-ZA\", \"thumbnails\": [{\"url\": \"https://i.ytimg.com/vi/Jouh2mdt1fI/hq720.jpg?sqp=-oaymwEcCOgCEMoBSFXyq4qpAw4IARUAAIhCGAFwAcABBg==&rs=AOn4CLAPEfEj6_EjWEq_78M77ogb3P8iEw\", \"height\": 202, \"width\": 360}, {\"url\": \"https://i.ytimg.com/vi/Jouh2mdt1fI/hq720.jpg?sqp=-oaymwEcCNAFEJQDSFXyq4qpAw4IARUAAIhCGAFwAcABBg==&rs=AOn4CLDmWrUVI_62g53kMu_yXalj63oOLA\", \"height\": 404, \"width\": 720}], \"timestamp\": null, \"release_timestamp\": null, \"availability\": null, \"view_count\": 1245513, \"live_status\": null, \"__x_forwarded_for_ip\": null, \"webpage_url\": \"https://www.youtube.com/watch?v=Jouh2mdt1fI\", \"original_url\": \"https://www.youtube.com/watch?v=Jouh2mdt1fI\", \"webpage_url_basename\": \"watch\", \"webpage_url_domain\": \"youtube.com\", \"extractor\": \"youtube\", \"extractor_key\": \"Youtube\", \"playlist_count\": null, \"playlist\": \"urban rescue ranch\", \"playlist_id\": \"urban rescue ranch\", \"playlist_title\": \"urban rescue ranch\", \"playlist_uploader\": null, \"playlist_uploader_id\": null, \"n_entries\": 10, \"playlist_index\": 2, \"__last_playlist_index\": 10, \"playlist_autonumber\": 2, \"duration_string\": \"10:12\", \"epoch\": 1687803719, \"filename\": \"How to Cook Capybara Pie (eating Big Ounce) [Jouh2mdt1fI].NA\", \"urls\": \"https://www.youtube.com/watch?v=Jouh2mdt1fI\", \"_version\": {\"version\": \"2023.03.04\", \"current_git_head\": null, \"release_git_head\": \"392389b7df7b818f794b231f14dc396d4875fbad\", \"repository\": \"yt-dlp/yt-dlp\"}}"
  @video_data_2 "{\"_type\": \"url\", \"ie_key\": \"Youtube\", \"id\": \"Jouh2mdt1fz\", \"url\": \"https://www.youtube.com/watch?v=Jouh2mdt1fI\", \"title\": \"How to Cook Capybara Pie (eating Big Ounce)\", \"description\": null, \"duration\": 612.0, \"channel_id\": \"UCv3mh2P-q3UCtR9-2q8B-ZA\", \"channel\": \"The Urban Rescue Ranch\", \"channel_url\": \"https://www.youtube.com/channel/UCv3mh2P-q3UCtR9-2q8B-ZA\", \"thumbnails\": [{\"url\": \"https://i.ytimg.com/vi/Jouh2mdt1fI/hq720.jpg?sqp=-oaymwEcCOgCEMoBSFXyq4qpAw4IARUAAIhCGAFwAcABBg==&rs=AOn4CLAPEfEj6_EjWEq_78M77ogb3P8iEw\", \"height\": 202, \"width\": 360}, {\"url\": \"https://i.ytimg.com/vi/Jouh2mdt1fI/hq720.jpg?sqp=-oaymwEcCNAFEJQDSFXyq4qpAw4IARUAAIhCGAFwAcABBg==&rs=AOn4CLDmWrUVI_62g53kMu_yXalj63oOLA\", \"height\": 404, \"width\": 720}], \"timestamp\": null, \"release_timestamp\": null, \"availability\": null, \"view_count\": 1245513, \"live_status\": null, \"__x_forwarded_for_ip\": null, \"webpage_url\": \"https://www.youtube.com/watch?v=Jouh2mdt1fI\", \"original_url\": \"https://www.youtube.com/watch?v=Jouh2mdt1fI\", \"webpage_url_basename\": \"watch\", \"webpage_url_domain\": \"youtube.com\", \"extractor\": \"youtube\", \"extractor_key\": \"Youtube\", \"playlist_count\": null, \"playlist\": \"urban rescue ranch\", \"playlist_id\": \"urban rescue ranch\", \"playlist_title\": \"urban rescue ranch\", \"playlist_uploader\": null, \"playlist_uploader_id\": null, \"n_entries\": 10, \"playlist_index\": 2, \"__last_playlist_index\": 10, \"playlist_autonumber\": 2, \"duration_string\": \"10:12\", \"epoch\": 1687803719, \"filename\": \"How to Cook Capybara Pie (eating Big Ounce) [Jouh2mdt1fI].NA\", \"urls\": \"https://www.youtube.com/watch?v=Jouh2mdt1fI\", \"_version\": {\"version\": \"2023.03.04\", \"current_git_head\": null, \"release_git_head\": \"392389b7df7b818f794b231f14dc396d4875fbad\", \"repository\": \"yt-dlp/yt-dlp\"}}"
  @video_data_3 "{\"_type\": \"url\", \"ie_key\": \"Youtube\", \"id\": \"9HO61id2TTQ\", \"url\": \"https://www.youtube.com/watch?v=9HO61id2TTQ\", \"title\": \"I\u2019ve Had Enough.\", \"description\": \"I have eaten Kevin.\\n\\n\\nWarm regards,\\nUncle farmer dad Ben \\ud83d\\udc68\\ud83c\\udffb\\u200d\\ud83c\\udf3e\\ud83e\\udd1d\\n\\nDONT SUBSCRIBE TO THIS CRINGE FAKE CHANNEL!!!:\\nhttps://www.youtube.com/channel/UCmTTgL4AolBts0ETnlWx3ow\\n\\nWe Finally...\", \"duration\": 639.0, \"channel_id\": null, \"channel\": null, \"channel_url\": null, \"thumbnails\": [{\"url\": \"https://i.ytimg.com/vi/9HO61id2TTQ/hqdefault.jpg?sqp=-oaymwEbCKgBEF5IVfKriqkDDggBFQAAiEIYAXABwAEG&rs=AOn4CLDsF3hBAxouqVmISxx6R9Fv2HOGCQ\", \"height\": 94, \"width\": 168}, {\"url\": \"https://i.ytimg.com/vi/9HO61id2TTQ/hqdefault.jpg?sqp=-oaymwEbCMQBEG5IVfKriqkDDggBFQAAiEIYAXABwAEG&rs=AOn4CLA4Xi7pnkMgoe3-9dHel90xusEClg\", \"height\": 110, \"width\": 196}, {\"url\": \"https://i.ytimg.com/vi/9HO61id2TTQ/hqdefault.jpg?sqp=-oaymwEcCPYBEIoBSFXyq4qpAw4IARUAAIhCGAFwAcABBg==&rs=AOn4CLC5u1ySrIcKemiHtbHrRe0VScYd8g\", \"height\": 138, \"width\": 246}, {\"url\": \"https://i.ytimg.com/vi/9HO61id2TTQ/hqdefault.jpg?sqp=-oaymwEcCNACELwBSFXyq4qpAw4IARUAAIhCGAFwAcABBg==&rs=AOn4CLDufQui7imFEFw_Y9E4mfFfBSHF4A\", \"height\": 188, \"width\": 336}], \"timestamp\": null, \"release_timestamp\": null, \"availability\": null, \"view_count\": 510271, \"live_status\": null, \"__x_forwarded_for_ip\": null, \"webpage_url\": \"https://www.youtube.com/watch?v=9HO61id2TTQ\", \"original_url\": \"https://www.youtube.com/watch?v=9HO61id2TTQ\", \"webpage_url_basename\": \"watch\", \"webpage_url_domain\": \"youtube.com\", \"extractor\": \"youtube\", \"extractor_key\": \"Youtube\", \"playlist_count\": null, \"playlist\": \"The Urban Rescue Ranch - Videos\", \"playlist_id\": \"UCv3mh2P-q3UCtR9-2q8B-ZA\", \"playlist_title\": \"The Urban Rescue Ranch - Videos\", \"playlist_uploader\": \"The Urban Rescue Ranch\", \"playlist_uploader_id\": \"UCv3mh2P-q3UCtR9-2q8B-ZA\", \"n_entries\": 15, \"playlist_index\": 1, \"__last_playlist_index\": 15, \"playlist_autonumber\": 1, \"duration_string\": \"10:39\", \"epoch\": 1688142651, \"filename\": \"I\u2019ve Had Enough. [9HO61id2TTQ].NA\", \"urls\": \"https://www.youtube.com/watch?v=9HO61id2TTQ\", \"_version\": {\"version\": \"2023.03.04\", \"current_git_head\": null, \"release_git_head\": \"392389b7df7b818f794b231f14dc396d4875fbad\", \"repository\": \"yt-dlp/yt-dlp\"}}"
  @test_output "#{@channel_data}\n#{@video_data}\n#{@video_data_2}"
  @channel_test_output "#{@video_data_3}"

  defp assert_int_or_null(nil), do: nil

  defp assert_int_or_null(value) do
    {_, ""} = Integer.parse(value)
  end

  defp verify_single_result(given, expected) do
    # validate they're integers at least
    assert_int_or_null(given["slot_id"])
    assert_int_or_null(given["channel_slot"])

    given_without_slot_id =
      given
      |> Map.delete("slot_id")
      |> Map.delete("channel_slot")

    assert given_without_slot_id == expected
  end

  defp verify_search_results(json_response) do
    verify_single_result(json_response["search_results"] |> Enum.at(0), %{
      "type" => "channel",
      "channel_name" => "The Urban Rescue Ranch",
      "description" =>
        "I have a tiny urban rescue ranch/homestead in central Texas. Join me as i create and manage the homestead and all of its ...",
      "duration" => nil,
      "title" => "The Urban Rescue Ranch",
      "type" => "channel",
      "uploaded_at" => nil,
      "view_count" => nil,
      "youtube_id" => "UCv3mh2P-q3UCtR9-2q8B-ZA",
      "youtube_url" => "https://www.youtube.com/channel/UCv3mh2P-q3UCtR9-2q8B-ZA",
      "thumbnail" => %{"aspect_ratio" => 1.0}
    })

    verify_single_result(json_response["search_results"] |> Enum.at(1), %{
      "type" => "video",
      "duration" => 612.0,
      "title" => "How to Cook Capybara Pie (eating Big Ounce)",
      "youtube_id" => "Jouh2mdt1fI",
      "youtube_url" => "https://www.youtube.com/watch?v=Jouh2mdt1fI",
      "channel_name" => "The Urban Rescue Ranch",
      "description" => nil,
      "uploaded_at" => nil,
      "view_count" => 1_245_513,
      "thumbnail" => %{"aspect_ratio" => 1.7821782178217822}
    })

    verify_single_result(
      json_response["search_results"] |> Enum.at(2),
      %{
        "type" => "video",
        "duration" => 612.0,
        "title" => "How to Cook Capybara Pie (eating Big Ounce)",
        "youtube_id" => "Jouh2mdt1fz",
        "youtube_url" => "https://www.youtube.com/watch?v=Jouh2mdt1fI",
        "channel_name" => "The Urban Rescue Ranch",
        "description" => nil,
        "uploaded_at" => nil,
        "view_count" => 1_245_513,
        "thumbnail" => %{"aspect_ratio" => 1.7821782178217822}
      }
    )

    assert json_response["slot_id"] != nil
  end

  def verify_channel_results(json_response) do
    desc =
      "\"Uncle farmer dad Ben \\ud83d\\udc68\\ud83c\\udffb\\u200d\\ud83c\\udf3e\\ud83e\\udd1d\\n\\nDONT SUBSCRIBE TO THIS\""
      |> Jason.decode!()

    verify_single_result(
      json_response["search_results"] |> Enum.at(0),
      %{
        "channel_name" => nil,
        "description" =>
          "I have eaten Kevin.\n\n\nWarm regards,\n" <>
            desc <>
            " CRINGE FAKE CHANNEL!!!:\nhttps://www.youtube.com/channel/UCmTTgL4AolBts0ETnlWx3ow\n\nWe Finally...",
        "duration" => 639.0,
        "title" => "I’ve Had Enough.",
        "type" => "video",
        "uploaded_at" => nil,
        "view_count" => 510_271,
        "youtube_id" => "9HO61id2TTQ",
        "youtube_url" => "https://www.youtube.com/watch?v=9HO61id2TTQ",
        "thumbnail" => %{"aspect_ratio" => 1.7872340425531914}
      }
    )

    assert json_response["slot_id"] != nil
  end

  test "it does the thing", %{conn: conn} do
    with_mock(
      System,
      [:passthrough],
      cmd: fn _, args ->
        search_term = args |> Enum.at(0)

        if String.contains?(search_term, "/channel/") do
          {@channel_test_output, 0}
        else
          {@test_output, 0}
        end
      end
    ) do
      conn =
        conn
        |> get(~p"/api/v1/search?search=urban+rescue+ranch")

      resp_json = json_response(conn, 200)
      verify_search_results(resp_json)
      second_slot_id = resp_json["search_results"] |> Enum.at(2) |> Access.get("slot_id")

      conn =
        conn
        |> get("/api/v1/s/#{second_slot_id}")

      assert get_resp_header(conn, "location") == ["https://youtube.com/watch?v=Jouh2mdt1fz"]

      first_result = resp_json["search_results"] |> Enum.at(0)
      assert first_result["type"] == "channel"
      first_slot_id = first_result |> Access.get("slot_id")

      conn =
        conn
        |> get("/a/1/c/#{first_slot_id}")

      verify_channel_results(json_response(conn, 200))
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
