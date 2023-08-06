defmodule YtSearchWeb.SearchTest do
  use YtSearchWeb.ConnCase, async: false

  defp assert_int_or_null(nil), do: nil

  defp assert_int_or_null(value) do
    {_, ""} = Integer.parse(value)
  end

  defp verify_single_result(given, expected) do
    # validate they're integers at least
    {_, ""} = Integer.parse(given["slot_id"])
    assert_int_or_null(given["channel_slot"])

    given_without_slot_id =
      given
      |> Map.delete("slot_id")
      |> Map.delete("channel_slot")
      |> Map.delete("description")

    case expected["description"] do
      {:starts_with, prefix} ->
        assert String.starts_with?(given["description"], prefix)

      data ->
        assert given["description"] == data
    end

    assert given_without_slot_id == expected |> Map.delete("description")
  end

  defp verify_search_results(json_response) do
    assert is_map(json_response)

    verify_single_result(json_response["search_results"] |> Enum.at(1), %{
      "type" => "channel",
      "channel_name" => "The Urban Rescue Ranch",
      "description" =>
        "I bought a crackhouse and dump and turned it into a Certified wildlife rehabilitation facility and farm sanctuary for exotic (hunted) ...",
      "title" => "The Urban Rescue Ranch",
      "youtube_id" => "UCv3mh2P-q3UCtR9-2q8B-ZA",
      "thumbnail" => %{"aspect_ratio" => 1.77},
      "subscriber_count" => 2_640_000
    })

    verify_single_result(json_response["search_results"] |> Enum.at(0), %{
      "type" => "video",
      "duration" => 638,
      "title" => "I Fed a Bat to My Prairie Dog (Big Ounce Dies)",
      "youtube_id" => "E-iZ-MPQu1Y",
      "channel_name" => "The Urban Rescue Ranch",
      # for some reason direct string equals does not work...
      "description" => {:starts_with, "Big ounce has fallen"},
      "uploaded_at" => 1_691_278_211,
      "view_count" => 38490,
      "thumbnail" => %{"aspect_ratio" => 1.77}
    })

    verify_single_result(
      json_response["search_results"] |> Enum.at(2),
      %{
        "channel_name" => "The Urban Rescue Ranch",
        "description" =>
          "Dont forget to like this vidja and to pray for the animals tonight before bed! It will be -9° windchills! Love, Uncle Farmer Dad Ben ...",
        "duration" => 788,
        "thumbnail" => %{"aspect_ratio" => 1.77},
        "title" => "This Kangaroo Saved my Life (dababy kills Kevin)",
        "type" => "video",
        "uploaded_at" => 1_672_963_200,
        "view_count" => 3_384_156,
        "youtube_id" => "ClEcGfH1250"
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
        "channel_name" => "The Urban Rescue Ranch",
        "description" =>
          "Big ounce has fallen 😖\n\nLove,\nUncle Farmer Dad Ben 👨🏻‍🌾\n\nCheck out Austin Bat Refuge if you’d like to support them!:\nhttps://austinbatrefuge.org/donations/\n\nSUBSCRIMBO TO GORTS...",
        "duration" => 638,
        "thumbnail" => %{"aspect_ratio" => 1.77},
        "title" => "I Fed a Bat to My Prairie Dog (Big Ounce Dies)",
        "type" => "video",
        "uploaded_at" => 1_691_278_208,
        "view_count" => 40177,
        "youtube_id" => "E-iZ-MPQu1Y"
      }
    )

    assert json_response["slot_id"] != nil
  end

  @piped_search_output File.read!("test/support/piped_outputs/urban_rescue_ranch_search.json")
  @piped_channel_output File.read!(
                          "test/support/piped_outputs/the_urban_rescue_ranch_channel.json"
                        )
  import Tesla.Mock

  test "it does the thing", %{conn: conn} do
    # TODO review if we can enable async tests by moving away from mock
    # and into Tesla.Mock
    mock(fn
      %{method: :get, url: "example.org" <> suffix} ->
        if String.contains?(suffix, "/channel/") do
          json(Jason.decode!(@piped_channel_output))
        else
          json(Jason.decode!(@piped_search_output))
        end
    end)

    conn =
      conn
      |> put_req_header("user-agent", "UnityWebRequest")
      |> get(~p"/api/v1/search?search=urban+rescue+ranch")

    resp_json = json_response(conn, 200)
    verify_search_results(resp_json)
    second_slot_id = resp_json["search_results"] |> Enum.at(2) |> Access.get("slot_id")

    conn =
      conn
      |> get("/api/v1/s/#{second_slot_id}")

    assert get_resp_header(conn, "location") == ["https://youtube.com/watch?v=ClEcGfH1250"]

    first_result = resp_json["search_results"] |> Enum.at(1)
    assert first_result["type"] == "channel"
    first_slot_id = first_result |> Access.get("slot_id")

    conn =
      conn
      |> get("/a/1/c/#{first_slot_id}")

    verify_channel_results(json_response(conn, 200))
  end

  test "small route", %{conn: conn} do
    mock(fn
      %{method: :get, url: "example.org" <> suffix} ->
        json(Jason.decode!(@piped_search_output))
    end)

    conn =
      conn
      |> put_req_header("user-agent", "UnityWebRequest")
      |> get(~p"/a/1/s?q=urban+rescue+ranch")

    assert verify_search_results(json_response(conn, 200))
  end

  test "fails on non-UnityWebRequest", %{conn: conn} do
    conn =
      conn
      |> get(~p"/a/1/s?q=urban+rescue+ranch")

    rjson = json_response(conn, 400)
    assert rjson["error"]
  end

  test "ytdlp ratelimiting works" do
    # need to use mock_global because this test involved multiple process
    Tesla.Mock.mock_global(fn
      %{method: :get, url: "example.org/search?q=amongus_test&filter=all"} ->
        Process.sleep(2)
        json(Jason.decode!(@piped_search_output))
    end)

    # setup
    original_limits = Application.fetch_env!(:yt_search, YtSearch.Ratelimit)
    Application.put_env(:yt_search, YtSearch.Ratelimit, ytdlp_search: {2, 4})

    ratelimited_requests =
      1..20
      |> Enum.map(fn _ ->
        Task.async(fn ->
          Phoenix.ConnTest.build_conn()
          |> put_req_header("user-agent", "UnityWebRequest")
          |> get(~p"/a/1/s?q=amongus_test")
        end)
      end)
      |> Enum.map(fn task ->
        conn = Task.await(task)
        # for non-200 searches, assert they make sense
        if conn.status == 200 do
          resp_json = json_response(conn, 200)
          verify_search_results(resp_json)
        end

        conn.status
      end)
      |> Enum.filter(fn status -> status == 429 end)

    assert length(ratelimited_requests) > 0

    Application.put_env(:yt_search, YtSearch.Ratelimit, original_limits)

    # attempt to test the SearchSlot storage by making a request after the main one
    conn =
      Phoenix.ConnTest.build_conn()
      |> put_req_header("user-agent", "UnityWebRequest")
      |> get(~p"/a/1/s?q=amongus_test")

    resp_json = json_response(conn, 200)
    verify_search_results(resp_json)
  end

  @piped_topic_channel File.read!("test/support/piped_outputs/topic_channel_search.json")

  test "it doesn't provide topic channel results", %{conn: conn} do
    mock(fn
      %{method: :get, url: "example.org/search" <> suffix} ->
        json(Jason.decode!(@piped_topic_channel))
    end)

    conn =
      conn
      |> put_req_header("user-agent", "UnityWebRequest")
      |> get(~p"/a/1/s?q=whatever")

    rjson = json_response(conn, 200)
    # the original response containns 20, the channel entry is the only removed
    assert length(rjson["search_results"]) == 19
  end

  @piped_upcoming_premiere File.read!(
                             "test/support/piped_outputs/upcoming_premiere_in_search.json"
                           )
  test "it doesn't provide premieres", %{conn: conn} do
    mock(fn
      %{method: :get, url: "example.org/search" <> suffix} ->
        json(Jason.decode!(@piped_upcoming_premiere))
    end)

    conn =
      conn
      |> put_req_header("user-agent", "UnityWebRequest")
      |> get(~p"/a/1/s?q=whatever")

    rjson = json_response(conn, 200)
    assert length(rjson["search_results"]) == 19
  end
end
