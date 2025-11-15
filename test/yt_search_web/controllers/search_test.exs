defmodule YtSearchWeb.SearchTest do
  alias YtSearch.SearchSlot
  use YtSearchWeb.ConnCase, async: false
  alias YtSearch.Test.Data
  alias YtSearch.{Slot, ChannelSlot, PlaylistSlot}
  alias YtSearch.Data.SearchSlotRepo
  import Ecto.Query

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
    assert json_response["result_type"] == "channel"
    assert json_response["result_title"] == "The Urban Rescue Ranch"

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

  defp verify_miku_search_results(json_response) do
    verify_single_result(
      json_response["search_results"] |> Enum.at(6),
      %{
        "channel_name" => "Vaush",
        "duration" => 1854,
        "thumbnail" => %{"aspect_ratio" => 1.77},
        "title" => "HATSUNE MIKU DEFEATS RACISM",
        "type" => "video",
        "uploaded_at" => 1_724_770_272,
        "view_count" => 78413,
        "youtube_id" => "zRwxQRWCzZ8"
      }
    )
  end

  defp verify_tomscott_search_results(json_response) do
    verify_single_result(
      json_response["search_results"] |> Enum.at(3),
      %{
        "channel_name" => "Tom Scott",
        "duration" => 324,
        "thumbnail" => %{"aspect_ratio" => 1.77},
        "title" => "A robot just swapped my electric car's battery",
        "type" => "video",
        "uploaded_at" => 1_704_762_000,
        "view_count" => 1_869_524,
        "youtube_id" => "hNZy603as5w"
      }
    )
  end

  @piped_search_output File.read!("test/support/piped_outputs/urban_rescue_ranch_search.json")
  @miku_search_output File.read!("test/support/piped_outputs/hatsune_miku_search.json")
  @notitg_search_output File.read!("test/support/piped_outputs/notitg_search.json")
  @piped_channel_output File.read!(
                          "test/support/piped_outputs/the_urban_rescue_ranch_channel.json"
                        )
  @tomscott_channel_output File.read!("test/support/piped_outputs/tom_scott_channel.json")
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
      |> get(~p"/api/v6/search?search=urban+rescue+ranch")

    resp_json = json_response(conn, 200)
    verify_search_results(resp_json)
    assert length(resp_json["search_results"]) == 19
    second_slot_id = resp_json["search_results"] |> Enum.at(2) |> Access.get("slot_id")

    conn =
      conn
      |> get("/api/v6/s/#{second_slot_id}")

    assert get_resp_header(conn, "location") == ["https://youtube.com/watch?v=ClEcGfH1250"]

    first_result = resp_json["search_results"] |> Enum.at(1)
    assert first_result["type"] == "channel"
    first_slot_id = first_result |> Access.get("slot_id")

    conn =
      conn
      |> get("/a/6/c/#{first_slot_id}")

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
      |> get(~p"/a/6/s?q=urban+rescue+ranch")

    assert verify_search_results(json_response(conn, 200))
  end

  test "fails on non-UnityWebRequest", %{conn: conn} do
    conn =
      conn
      |> get(~p"/a/6/s?q=urban+rescue+ranch")

    rjson = json_response(conn, 400)
    assert rjson["error"]
  end

  test "VRChat user-agent works like UnityWebRequest", %{conn: conn} do
    mock(fn
      %{method: :get, url: "example.org" <> _suffix} ->
        json(Jason.decode!(@piped_search_output))
    end)

    conn =
      conn
      |> put_req_header("user-agent", "VRChat/2024.1.1")
      |> get(~p"/a/6/s?q=urban+rescue+ranch")

    assert verify_search_results(json_response(conn, 200))
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
          |> get(~p"/a/6/s?q=amongus_test")
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
      |> get(~p"/a/6/s?q=amongus_test")

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
      |> get(~p"/a/6/s?q=whatever")

    rjson = json_response(conn, 200)

    rjson["search_results"]
    |> Enum.each(fn res ->
      assert res["youtube_id"] != "UCE-0bs8PtC2nWFgXwtkCUAA"
    end)
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
      |> get(~p"/a/6/s?q=whatever")

    rjson = json_response(conn, 200)

    rjson["search_results"]
    |> Enum.each(fn res ->
      assert res["youtube_id"] != "_SvFetHaJpo"
    end)
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
      |> get(~p"/a/6/s?q=amongus_test%233")

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
        |> get(~p"/api/v6/search?search=whatever")

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
        |> get(~p"/api/v6/search?search=whatever")

      rjson = json_response(conn, 200)
      first_result = rjson["search_results"] |> Enum.at(0)
      assert first_result["type"] == "livestream"
      slot = YtSearch.Slot.fetch_by_id(first_result["slot_id"])
      assert slot != nil
      delta = NaiveDateTime.diff(slot.expires_at, NaiveDateTime.utc_now())
      assert delta >= 20 * 60
    end
  end)

  test "user can fetch nextpage", %{conn: conn, ets_table: table} do
    mock(fn
      %{method: :get, url: "example.org/channel/" <> _whatever} ->
        json(Jason.decode!(@piped_channel_output))

      %{method: :get, url: "example.org/search" <> _whatever} ->
        json(Jason.decode!(@piped_search_output))

      %{method: :get, url: "example.org/nextpage/search" <> _whatever} ->
        calls = :ets.update_counter(table, :nextpage, 1, {:nextpage, 0})

        json(
          case calls do
            1 ->
              Jason.decode!(@miku_search_output)

            2 ->
              %{
                items: [],
                nextpage: "null",
                suggestion: "",
                corrected: false
              }
          end
        )
    end)

    conn =
      conn
      |> put_req_header("user-agent", "UnityWebRequest")
      |> get(~p"/api/v6/search?search=urban+rescue+ranch")

    resp_json = json_response(conn, 200)
    # it must NOT call the nextpage handler, yet.
    assert :ets.lookup(table, :nextpage) == []
    verify_search_results(resp_json)

    nextpage_slot = resp_json["nextpage_slot_id"]
    assert nextpage_slot != nil

    # fetch first nextpage twice to assert both return the same data
    # and dont call nextpage twice internally
    conn =
      build_conn()
      |> put_req_header("user-agent", "UnityWebRequest")
      |> get(~p"/api/v6/search/#{nextpage_slot}")

    resp_json = json_response(conn, 200)

    conn2 =
      build_conn()
      |> put_req_header("user-agent", "UnityWebRequest")
      |> get(~p"/api/v6/search/#{nextpage_slot}")

    resp_json2 = json_response(conn2, 200)
    assert :ets.lookup(table, :nextpage) == [nextpage: 1]

    YtSearch.AssertUtil.equal_search_responses(resp_json, resp_json2)
    verify_miku_search_results(resp_json)

    nextpage_slot = resp_json["nextpage_slot_id"]
    assert nextpage_slot != nil

    # fetch yet again, which will return nothing and nil nextpage
    conn =
      build_conn()
      |> put_req_header("user-agent", "UnityWebRequest")
      |> get(~p"/api/v6/search/#{nextpage_slot}")

    resp_json = json_response(conn, 200)
    assert :ets.lookup(table, :nextpage) == [nextpage: 2]
    assert length(resp_json["search_results"]) == 0

    nextpage_slot = resp_json["nextpage_slot_id"]
    assert nextpage_slot == nil
  end

  test "user can fetch nextpage for channels", %{conn: conn, ets_table: table} do
    mock(fn
      %{method: :get, url: "example.org/search" <> _whatever} ->
        json(Jason.decode!(@piped_search_output))

      %{method: :get, url: "example.org/channel/" <> _whatever} ->
        json(Jason.decode!(@piped_channel_output))

      %{method: :get, url: "example.org/nextpage/channel" <> _whatever} ->
        calls = :ets.update_counter(table, :channel_nextpage, 1, {:channel_nextpage, 0})

        json(
          case calls do
            1 ->
              Jason.decode!(@tomscott_channel_output)

            2 ->
              %{
                relatedStreams: [],
                nextpage: nil
              }
          end
        )
    end)

    conn =
      conn
      |> put_req_header("user-agent", "UnityWebRequest")
      |> get(~p"/api/v6/search?search=urban+rescue+ranch")

    resp_json = json_response(conn, 200)
    # it must NOT call the channel nextpage handler, yet.
    assert :ets.lookup(table, :channel_nextpage) == []
    verify_search_results(resp_json)

    nextpage_slot = resp_json["nextpage_slot_id"]
    assert nextpage_slot != nil
    channel_slot = resp_json["search_results"] |> Enum.at(1) |> Access.get("channel_slot")
    assert channel_slot != nil

    # fetch channel, then fetch nextpages coming from it
    conn =
      build_conn()
      |> put_req_header("user-agent", "UnityWebRequest")
      |> get(~p"/a/6/c/#{channel_slot}")

    resp_json = json_response(conn, 200)
    assert :ets.lookup(table, :nextpage) == []
    verify_channel_results(resp_json)

    nextpage_slot = resp_json["nextpage_slot_id"]
    assert nextpage_slot != nil

    # fetch the nextpage twice, it should not request piped nextpage twice
    conn =
      build_conn()
      |> put_req_header("user-agent", "UnityWebRequest")
      |> get(~p"/a/6/r/#{nextpage_slot}")

    resp_json = json_response(conn, 200)

    conn2 =
      build_conn()
      |> put_req_header("user-agent", "UnityWebRequest")
      |> get(~p"/a/6/r/#{nextpage_slot}")

    resp_json2 = json_response(conn2, 200)
    assert :ets.lookup(table, :channel_nextpage) == [channel_nextpage: 1]
    YtSearch.AssertUtil.equal_search_responses(resp_json, resp_json2)
    verify_tomscott_search_results(resp_json)

    nextpage_slot = resp_json["nextpage_slot_id"]
    assert nextpage_slot != nil

    # fetch nextpage, which will return nothing and nil nextpage
    conn =
      build_conn()
      |> put_req_header("user-agent", "UnityWebRequest")
      |> get(~p"/a/6/r/#{nextpage_slot}")

    resp_json = json_response(conn, 200)
    assert :ets.lookup(table, :channel_nextpage) == [channel_nextpage: 2]
    assert length(resp_json["search_results"]) == 0

    nextpage_slot = resp_json["nextpage_slot_id"]
    assert nextpage_slot == nil
  end

  defp fetch_slot_expirations(%YtSearch.SearchSlot{} = result) do
    case result.type do
      :fetched ->
        fetch_slot_expirations(%{
          "slot_id" => "#{result.id}",
          "search_results" => SearchSlot.get_slots(result),
          "nextpage_slot_id" => result.nextpage_slot_id
        })

      :unfetched ->
        []
    end
  end

  defp fetch_slot_expirations(result),
    do:
      result["search_results"]
      |> Enum.map(fn item ->
        case item["type"] do
          "video" ->
            slot = Slot.fetch_by_id(item["slot_id"])
            child_slot = ChannelSlot.fetch(item["channel_slot"])

            [
              {:v, slot.id, slot.expires_at},
              {:c, child_slot.id, child_slot.expires_at}
            ]

          "channel" ->
            slot = ChannelSlot.fetch(item["slot_id"])

            [
              {:c, slot.id, slot.expires_at}
            ]

          "playlist" ->
            slot = PlaylistSlot.fetch(item["slot_id"])

            [
              {:p, slot.id, slot.expires_at}
            ]
        end
      end)
      |> List.flatten()
      |> then(fn list ->
        search_slot = YtSearch.SearchSlot.fetch(result["slot_id"])
        assert search_slot != nil

        case search_slot.nextpage_slot_id do
          nil ->
            list

          nextpage_id ->
            nextpage_slot = YtSearch.SearchSlot.fetch(nextpage_id)
            assert nextpage_slot != nil

            list ++
              [{:s, nextpage_id, nextpage_slot.expires_at}] ++
              fetch_slot_expirations(nextpage_slot)
        end
      end)

  test "it refreshes the child slots on new search", %{conn: conn, ets_table: table} do
    mock(fn
      %{method: :get, url: "example.org/search" <> _suffix} ->
        calls = :ets.update_counter(table, :notitg_search, 1, {:notitg_search, 0})

        case calls do
          1 -> json(Jason.decode!(@notitg_search_output))
          2 -> raise "requested search more than once, should've cached it"
        end

      %{method: :get, url: "example.org/nextpage/search" <> _whatever} ->
        calls = :ets.update_counter(table, :nextpage_child_test, 1, {:nextpage_child_test, 0})

        json(
          case calls do
            1 ->
              Jason.decode!(@miku_search_output)

            2 ->
              %{
                items: [],
                nextpage: "null",
                suggestion: "",
                corrected: false
              }
          end
        )
    end)

    conn =
      conn
      |> put_req_header("user-agent", "UnityWebRequest")
      |> get(~p"/a/6/s?q=urban+rescue+ranch")

    rjson_before = json_response(conn, 200)

    expirations_prenextpage_before =
      rjson_before
      |> fetch_slot_expirations

    # search the nextpage only once so we can validate *everything* was refreshed

    nextpage_slot_id = rjson_before["nextpage_slot_id"]

    conn =
      build_conn()
      |> put_req_header("user-agent", "UnityWebRequest")
      |> get(~p"/a/6/r/#{nextpage_slot_id}")

    _ = json_response(conn, 200)

    nextpage_slot = SearchSlot.fetch(nextpage_slot_id)
    assert nextpage_slot.type == :fetched

    expirations_before =
      rjson_before
      |> fetch_slot_expirations

    # nextpage should have at least 10 more
    assert length(expirations_before) > length(expirations_prenextpage_before) + 10

    Process.sleep(1000)

    # trigger a refresh by searching the same query

    conn =
      build_conn()
      |> put_req_header("user-agent", "UnityWebRequest")
      |> get(~p"/a/6/s?q=urban+rescue+ranch")

    rjson_after = json_response(conn, 200)

    expirations_after =
      rjson_after
      |> fetch_slot_expirations

    assert not Enum.empty?(expirations_before)

    Enum.with_index(expirations_before)
    |> Enum.map(fn {{before_type, before_id, before_expires_at}, index} ->
      {after_type, after_id, after_expires_at} = expirations_after |> Enum.at(index)
      assert before_id == after_id
      assert before_type == after_type
      assert before_expires_at != after_expires_at
    end)
  end

  @tag debug: true
  test "empty search slot is valid", %{conn: conn, ets_table: table} do
    mock(fn
      %{method: :get, url: "example.org/search" <> _suffix} ->
        calls = :ets.update_counter(table, :notitg_search, 1, {:notitg_search, 0})

        case calls do
          1 -> json(Jason.decode!(@notitg_search_output))
          2 -> raise "requested search more than once, should've cached it"
        end

      %{method: :get, url: "example.org/nextpage/search" <> _whatever} ->
        calls = :ets.update_counter(table, :nextpage_child_test, 1, {:nextpage_child_test, 0})

        json(
          case calls do
            1 ->
              %{
                items: [],
                nextpage: "null",
                suggestion: "",
                corrected: false
              }
          end
        )
    end)

    conn =
      conn
      |> put_req_header("user-agent", "UnityWebRequest")
      |> get(~p"/a/6/s?q=urban+rescue+ranch")

    rjson_root = json_response(conn, 200)

    nextpage_slot_id = rjson_root["nextpage_slot_id"]

    conn =
      build_conn()
      |> put_req_header("user-agent", "UnityWebRequest")
      |> get(~p"/a/6/r/#{nextpage_slot_id}")

    _ = json_response(conn, 200)

    nextpage_slot = SearchSlot.fetch(nextpage_slot_id)
    assert nextpage_slot.type == :fetched

    # fetching again should just work (the search slot is empty, it should be still valid)
    # prevents regression
    conn =
      build_conn()
      |> put_req_header("user-agent", "UnityWebRequest")
      |> get(~p"/a/6/r/#{nextpage_slot_id}")

    _ = json_response(conn, 200)

    nextpage_slot = SearchSlot.fetch(nextpage_slot_id)
    assert nextpage_slot.type == :fetched
  end

  def assert_all_slots_make_sense,
    do:
      from(s in SearchSlot, select: s)
      |> SearchSlotRepo.all()
      |> Enum.each(fn s ->
        case s.type do
          :fetched ->
            assert String.starts_with?(s.query, "ytsearch://")
            assert s.nextpage_data_hash == nil
            assert s.nextpage_data == nil

          :unfetched ->
            assert s.query == "ytsearchslot://#{s.id}"
            assert String.length(s.nextpage_data_hash) > 0
            assert String.length(s.nextpage_data) > 0
        end
      end)

  test "it does not 'corrupt' a search slot", %{conn: conn, ets_table: table} do
    mock(fn
      %{method: :get, url: "example.org/search" <> _suffix} ->
        calls = :ets.update_counter(table, :notitg_search, 1, {:notitg_search, 0})

        case calls do
          _ ->
            json(Jason.decode!(@notitg_search_output))
            # 2 -> raise "requested search more than once, should've cached it"
        end

      %{method: :get, url: "example.org/nextpage/search" <> _whatever} ->
        calls = :ets.update_counter(table, :nextpage_child_test, 1, {:nextpage_child_test, 0})

        json(
          case calls do
            1 ->
              Jason.decode!(@miku_search_output)

            2 ->
              %{
                items: [],
                nextpage: "null",
                suggestion: "",
                corrected: false
              }
          end
        )
    end)

    from(s in SearchSlot, select: s)
    |> SearchSlotRepo.all()
    |> Enum.each(fn s ->
      s
      |> SearchSlot.changeset(%{
        slots_json: "",
        query: "ytsearchslot://#{s.id}",
        expires_at: NaiveDateTime.utc_now() |> NaiveDateTime.add(30),
        keepalive: false,
        nextpage_data: "EXAMPLE NEXTPAGE DATA EXAMPLE NEXTPAGE DATA",
        nextpage_data_hash: "EXAMPLE HASH EXAMPLE HASH",
        type: :unfetched,
        nextpage_slot_id: nil,
        result_type: nil,
        result_title: nil
      })
      |> SearchSlotRepo.update!()
    end)

    assert_all_slots_make_sense()

    conn =
      conn
      |> put_req_header("user-agent", "UnityWebRequest")
      |> get(~p"/a/6/s?q=urban+rescue+ranch")

    rjson = json_response(conn, 200)
    slot = rjson["slot_id"] |> SearchSlot.fetch()
    assert slot.type == :fetched

    assert_all_slots_make_sense()

    # force-expire the search slot, try again
    slot
    |> SearchSlot.changeset(%{
      expires_at: NaiveDateTime.utc_now() |> NaiveDateTime.add(-300_00)
    })
    |> SearchSlotRepo.update!()

    # we should be reusing the previous slot
    conn =
      build_conn()
      |> put_req_header("user-agent", "UnityWebRequest")
      |> get(~p"/a/6/s?q=urban+rescue+ranch")

    rjson = json_response(conn, 200)
    slot_after = rjson["slot_id"] |> SearchSlot.fetch()
    assert slot.id == slot_after.id
    assert slot_after.type == :fetched

    assert_all_slots_make_sense()
  end
end
