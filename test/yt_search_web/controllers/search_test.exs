defmodule YtSearchWeb.SearchTest do
  use YtSearchWeb.ConnCase, async: false
  import Mock

  @test_output File.read!("test/support/files/the_urban_rescue_ranch_search.json")
  @channel_test_output File.read!("test/support/files/the_urban_rescue_ranch_channel.json")

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

    assert given_without_slot_id == expected
  end

  defp verify_search_results(json_response) do
    assert is_map(json_response)

    verify_single_result(json_response["search_results"] |> Enum.at(0), %{
      "type" => "channel",
      "channel_name" => "The Urban Rescue Ranch",
      "description" =>
        "I bought a crackhouse and dump and turned it into a Certified wildlife rehabilitation facility and farm sanctuary for exotic (hunted) ...",
      "duration" => nil,
      "title" => "The Urban Rescue Ranch",
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
      "view_count" => 1_251_497,
      "thumbnail" => %{"aspect_ratio" => 1.7821782178217822}
    })

    verify_single_result(
      json_response["search_results"] |> Enum.at(2),
      %{
        "channel_name" => "The Urban Rescue Ranch",
        "description" => nil,
        "duration" => 721.0,
        "thumbnail" => %{"aspect_ratio" => 1.7821782178217822},
        "title" => "I Sold Big Ounce (to gamble)",
        "type" => "video",
        "uploaded_at" => nil,
        "view_count" => 616_938,
        "youtube_id" => "ZQxcKNW2f08",
        "youtube_url" => "https://www.youtube.com/watch?v=ZQxcKNW2f08"
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
          "WE DID IT REDDIT\n\nLove,\nUncle Farmer Dad Ben 👨🏻‍🌾\n\nSUBSCRIMBO TO GORTS MUKBANG CHANNEL: \nhttps://www.youtube.com/channel/UCmTTgL4AolBts0ETnlWx3ow\n\nWe Finally Have DRIPPY Merch Again!...",
        "duration" => 635.0,
        "thumbnail" => %{"aspect_ratio" => 1.7872340425531914},
        "title" => "Big Ounce Goes to the Gym (Drowns at Bass Pro Shops)",
        "type" => "video",
        "uploaded_at" => nil,
        "view_count" => 349_643,
        "youtube_id" => "3Al_s6Uk_Dg",
        "youtube_url" => "https://www.youtube.com/watch?v=3Al_s6Uk_Dg"
      }
    )

    assert json_response["slot_id"] != nil
  end

  test "it does the thing", %{conn: conn} do
    with_mock(
      :exec,
      run: fn args, opts ->
        search_term = args |> Enum.at(1)

        if String.contains?(search_term, "/channel/") do
          {:ok, [stdout: [@channel_test_output]]}
        else
          {:ok, [stdout: [@test_output]]}
        end
      end
    ) do
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

      assert get_resp_header(conn, "location") == ["https://youtube.com/watch?v=ZQxcKNW2f08"]

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
      :exec,
      run: fn _, _ ->
        {:ok, [stdout: [@test_output]]}
      end
    ) do
      conn =
        conn
        |> put_req_header("user-agent", "UnityWebRequest")
        |> get(~p"/a/1/s?q=urban+rescue+ranch")

      assert verify_search_results(json_response(conn, 200))
    end
  end

  test "fails on non-UnityWebRequest", %{conn: conn} do
    conn =
      conn
      |> get(~p"/a/1/s?q=urban+rescue+ranch")

    rjson = json_response(conn, 400)
    assert rjson["error"]
  end

  test "ytdlp ratelimiting works" do
    with_mock(
      :exec,
      run: fn _, _ ->
        # synthetic load
        Process.sleep(2)
        {:ok, [stdout: [@test_output]]}
      end
    ) do
      # setup
      original_limits = Application.fetch_env!(:yt_search, YtSearch.Ratelimit)
      Application.put_env(:yt_search, YtSearch.Ratelimit, ytdlp_search: {2, 4})

      ratelimited_requests =
        1..20
        |> Enum.map(fn _ ->
          Task.async(fn ->
            Phoenix.ConnTest.build_conn()
            |> put_req_header("user-agent", "UnityWebRequest")
            |> get(~p"/a/1/s?q=urban+rescue+ranch")
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
        |> get(~p"/a/1/s?q=urban+rescue+ranch")

      resp_json = json_response(conn, 200)
      verify_search_results(resp_json)
    end
  end

  @topic_channel File.read!("test/support/files/search_for_topic_channel.json")

  test "it doesn't provide topic channel results", %{conn: conn} do
    with_mock(
      :exec,
      run: fn _, _ ->
        {:ok, [stdout: [@topic_channel]]}
      end
    ) do
      conn =
        conn
        |> put_req_header("user-agent", "UnityWebRequest")
        |> get(~p"/a/1/s?q=whatever")

      rjson = json_response(conn, 200)
      assert length(rjson["search_results"]) == 0
    end
  end

  @premiere_video File.read!("test/support/files/upcoming_premiere_in_search.json")
  test "it doesn't provide premieres", %{conn: conn} do
    with_mock(
      :exec,
      run: fn _, _ ->
        {:ok, [stdout: [@premiere_video]]}
      end
    ) do
      conn =
        conn
        |> put_req_header("user-agent", "UnityWebRequest")
        |> get(~p"/a/1/s?q=whatever")

      rjson = json_response(conn, 200)
      assert length(rjson["search_results"]) == 0
    end
  end
end
