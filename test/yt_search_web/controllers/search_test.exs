defmodule YtSearchWeb.SearchTest do
  use YtSearchWeb.ConnCase, async: false
  alias YtSearch.Test.Data

  setup do
    Tesla.Mock.mock_global(fn
      %{method: :get, url: "https://i.ytimg.com/" <> _} ->
        Data.png_response()

      %{method: :get, url: "https://yt3.ggpht.com/" <> _} ->
        Data.png_response()

      %{method: :get, url: "https://yt3.googleusercontent.com/" <> _} ->
        Data.png_response()

      %{method: :get, url: "https://i9.ytimg.com/" <> _} ->
        Data.png_response()
    end)

    ets = :ets.new(:mock_call_counter, [:public])
    %{ets_table: ets}
  end

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

      nil ->
        :noop

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
    verify_single_result(
      json_response["search_results"] |> Enum.at(0),
      %{
        "channel_name" => "The Urban Rescue Ranch",
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

  defp verify_long_search_results(json_response) do
    # verify_search_results(json_response)

    IO.inspect(json_response)

    verify_single_result(
      json_response["search_results"] |> Enum.at(33),
      %{
        "channel_name" => "Wilson (Low-key otaku)",
        "description" =>
          "Event title 初音ミク ライブパーティー 2012 「ミクパ」 Hatsune Miku Live Party 2012 (MikuPa) Date March 8 (MikuPa), ...",
        "duration" => 2678,
        "thumbnail" => %{"aspect_ratio" => 1.77},
        "title" => "Hatsune Miku Live at Coachella Week 1, 2024.",
        "type" => "video",
        "uploaded_at" => 1_714_276_800,
        "view_count" => 340_774,
        "youtube_id" => "IKW1h9THwVs"
      }
    )
  end

  @piped_search_output File.read!("test/support/piped_outputs/urban_rescue_ranch_search.json")
  @miku_search_output File.read!("test/support/piped_outputs/hatsune_miku_search.json")
  @piped_channel_output File.read!(
                          "test/support/piped_outputs/the_urban_rescue_ranch_channel.json"
                        )
  import Tesla.Mock

  test "it does the thing", %{conn: conn} do
    mock(fn
      %{method: :get, url: "example.org/channel/" <> _whatever} ->
        json(Jason.decode!(@piped_channel_output))

      %{method: :get, url: "example.org/search" <> _whatever} ->
        json(Jason.decode!(@piped_search_output))
    end)

    conn =
      conn
      |> put_req_header("user-agent", "UnityWebRequest")
      |> get(~p"/api/v5/search?search=urban+rescue+ranch")

    resp_json = json_response(conn, 200)
    verify_search_results(resp_json)
    assert length(resp_json["search_results"]) == 19
    second_slot_id = resp_json["search_results"] |> Enum.at(2) |> Access.get("slot_id")

    conn =
      conn
      |> get("/api/v5/s/#{second_slot_id}")

    assert get_resp_header(conn, "location") == ["https://youtube.com/watch?v=ClEcGfH1250"]

    first_result = resp_json["search_results"] |> Enum.at(1)
    assert first_result["type"] == "channel"
    first_slot_id = first_result |> Access.get("slot_id")

    conn =
      conn
      |> get("/a/5/c/#{first_slot_id}")

    verify_channel_results(json_response(conn, 200))
  end

  test "small route", %{conn: conn} do
    mock(fn
      %{method: :get, url: "example.org" <> _suffix} ->
        json(Jason.decode!(@piped_search_output))
    end)

    conn =
      conn
      |> put_req_header("user-agent", "UnityWebRequest")
      |> get(~p"/a/5/s?q=urban+rescue+ranch")

    assert verify_search_results(json_response(conn, 200))
  end

  test "fails on non-UnityWebRequest", %{conn: conn} do
    conn =
      conn
      |> get(~p"/a/5/s?q=urban+rescue+ranch")

    rjson = json_response(conn, 400)
    assert rjson["error"]
  end

  test "ytdlp ratelimiting works" do
    # need to use mock_global because this test involved multiple process
    Tesla.Mock.mock_global(fn
      %{method: :get, url: "example.org/search", query: [q: "amongus_test", filter: "all"]} ->
        Process.sleep(2)
        json(Jason.decode!(@piped_search_output))

      %{method: :get, url: "https://i.ytimg.com/" <> _} ->
        Data.png_response()

      %{method: :get, url: "https://yt3.ggpht.com/" <> _} ->
        Data.png_response()
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
          |> get(~p"/a/5/s?q=amongus_test")
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
      |> get(~p"/a/5/s?q=amongus_test")

    resp_json = json_response(conn, 200)
    verify_search_results(resp_json)
  end

  @piped_topic_channel File.read!("test/support/piped_outputs/topic_channel_search.json")

  test "it doesn't provide topic channel results", %{conn: conn} do
    mock(fn
      %{method: :get, url: "example.org/search" <> _suffix} ->
        json(Jason.decode!(@piped_topic_channel))
    end)

    conn =
      conn
      |> put_req_header("user-agent", "UnityWebRequest")
      |> get(~p"/a/5/s?q=whatever")

    rjson = json_response(conn, 200)
    # the original response containns 20, the channel entry is the only removed
    assert length(rjson["search_results"]) == 19
  end

  @piped_upcoming_premiere File.read!(
                             "test/support/piped_outputs/upcoming_premiere_in_search.json"
                           )
  test "it doesn't provide premieres", %{conn: conn} do
    mock(fn
      %{method: :get, url: "example.org/search" <> _suffix} ->
        json(Jason.decode!(@piped_upcoming_premiere))
    end)

    conn =
      conn
      |> put_req_header("user-agent", "UnityWebRequest")
      |> get(~p"/a/5/s?q=whatever")

    rjson = json_response(conn, 200)
    assert length(rjson["search_results"]) == 19
  end

  test "it encodes the search query properly", %{conn: conn} do
    Data.default_global_mock(fn
      %{method: :get, url: "example.org/search", query: [q: "amongus_test#3", filter: "all"]} ->
        json(Jason.decode!(@piped_search_output))

      %{method: :get, url: "example.org/search?q=amongus_test#3&filter=all"} ->
        json(%{"error" => "query and filter are required parameters"}, status: 400)
    end)

    conn =
      conn
      |> put_req_header("user-agent", "UnityWebRequest")
      |> get(~p"/a/5/s?q=amongus_test%233")

    json_response(conn, 200)
  end

  @test_cases [
    "lofi_search.json"
  ]

  @test_cases
  |> Enum.map(fn path -> "test/support/piped_outputs/#{path}" end)
  |> Enum.map(fn path -> {path, File.read!(path)} end)
  |> Enum.each(fn {path, file_data} ->
    test "it livestreams works on " <> path, %{conn: conn} do
      mock(fn
        %{method: :get, url: "example.org/search" <> _suffix} ->
          json(Jason.decode!(unquote(file_data)))
      end)

      conn =
        conn
        |> put_req_header("user-agent", "UnityWebRequest")
        |> get(~p"/api/v5/search?search=whatever")

      rjson = json_response(conn, 200)
      first_result = rjson["search_results"] |> Enum.at(0)
      assert first_result["type"] == "livestream"
      slot = YtSearch.Slot.fetch_by_id(first_result["slot_id"])
      assert slot != nil
      delta = NaiveDateTime.diff(slot.expires_at, NaiveDateTime.utc_now())
      assert delta >= 20 * 60

      slot
      |> Ecto.Changeset.change(
        expires_at:
          NaiveDateTime.utc_now()
          |> NaiveDateTime.add(-10, :second)
          |> NaiveDateTime.truncate(:second)
      )
      |> YtSearch.Data.SlotRepo.update!()

      conn =
        build_conn()
        |> put_req_header("user-agent", "UnityWebRequest")
        |> get(~p"/api/v5/search?search=whatever")

      rjson = json_response(conn, 200)
      first_result = rjson["search_results"] |> Enum.at(0)
      assert first_result["type"] == "livestream"
      slot = YtSearch.Slot.fetch_by_id(first_result["slot_id"])
      assert slot != nil
      delta = NaiveDateTime.diff(slot.expires_at, NaiveDateTime.utc_now())
      assert delta >= 20 * 60
    end
  end)

  test "nextpage works", %{conn: conn, ets_table: table} do
    mock(fn
      %{method: :get, url: "example.org/channel/" <> _whatever} ->
        json(Jason.decode!(@piped_channel_output))

      %{method: :get, url: "example.org/search" <> _whatever} ->
        # TODO (DO NOT MERGE) check parsmasm (must not have nextpage)
        json(Jason.decode!(@piped_search_output))

      %{method: :get, url: "example.org/nextpage/search" <> _whatever} ->
        :ets.update_counter(table, :nextpage, 1, {:nextpage, 0})
        json(Jason.decode!(@miku_search_output))
    end)

    existing_constants = Application.get_env(:yt_search, YtSearch.Constants)

    YtSearch.Constants.apply(
      existing_constants
      |> Keyword.put(:results_from_search, 35)
    )

    conn =
      conn
      |> put_req_header("user-agent", "UnityWebRequest")
      |> get(~p"/api/v5/search?search=urban+rescue+ranch")

    YtSearch.Constants.apply(existing_constants)

    resp_json = json_response(conn, 200)
    # it must call the nextpage handler
    assert :ets.lookup(table, :nextpage) == [nextpage: 1]
    verify_long_search_results(resp_json)
    assert length(resp_json["search_results"]) == 35
  end
end
