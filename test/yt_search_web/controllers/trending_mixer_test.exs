defmodule YtSearchWeb.TrendingMixerTest do
  @moduledoc """
  End-to-end tests for the trending mixer: hits /api/v6/hello-staging and
  verifies that YTS community-trending videos appear in the trending tab
  alongside upstream YouTube trending data. The mixer is currently only
  reachable via the staging endpoint — prod /hello still uses raw
  Youtube.trending().
  """
  use YtSearchWeb.ConnCase, async: false

  alias YtSearch.Data.TrendingRepo
  alias YtSearch.Trending
  alias YtSearch.Slot

  @upstream_trending File.read!("test/support/piped_outputs/trending_tab.json")

  setup do
    Cachex.del(:tabs, "trending")
    Cachex.del(:tabs, "staging_trending")
    TrendingRepo.query!("DELETE FROM video_counter")
    TrendingRepo.query!("DELETE FROM video_views")
    :ok
  end

  defp mock_piped_with_streams(stream_mocks \\ %{}) do
    upstream_data = Jason.decode!(@upstream_trending)

    Tesla.Mock.mock_global(fn
      %{method: :get, url: "example.org/trending", query: [region: "US"]} ->
        Tesla.Mock.json(upstream_data)

      %{method: :get, url: "example.org/streams/" <> video_id} ->
        case Map.get(stream_mocks, video_id) do
          nil -> %Tesla.Env{status: 500, body: %{"message" => "Video unavailable"}}
          response -> Tesla.Mock.json(response)
        end

      %{method: :get, url: "https://i.ytimg.com" <> _} ->
        YtSearch.Test.Data.png_response()

      %{method: :get, url: "https://yt3.ggpht.com" <> _} ->
        YtSearch.Test.Data.png_response()

      %{method: :get, url: "https://yt3.googleusercontent.com/ytc" <> _} ->
        YtSearch.Test.Data.png_response()

      %{method: :get, url: "https://pipedproxy" <> _} ->
        YtSearch.Test.Data.png_response()
    end)
  end

  defp piped_stream_response(youtube_id, title, opts \\ []) do
    %{
      "title" => title,
      "uploader" => opts[:uploader] || "TestChannel",
      "uploaderUrl" => opts[:uploader_url] || "/channel/UCtest123456",
      "duration" => opts[:duration] || 300,
      "views" => opts[:views] || 42,
      "description" => opts[:description] || "A test video",
      "thumbnailUrl" => "https://i.ytimg.com/vi/#{youtube_id}/hqdefault.jpg",
      "uploadDate" => opts[:upload_date] || "2026-04-10"
    }
  end

  defp fetch_trending(conn) do
    conn
    |> get(~p"/api/v6/hello-staging")
    |> json_response(200)
    |> get_in(["trending_tab", "search_results"])
  end

  test "trending tab works with no YTS view data (upstream-only fallback)", %{conn: conn} do
    mock_piped_with_streams()

    results = fetch_trending(conn)
    assert is_list(results)
    assert length(results) > 0

    # First upstream entry should still be present
    assert Enum.at(results, 0)["youtube_id"] == "HYzyRHAHJl8"

    # Every result should have a parseable slot_id
    Enum.each(results, fn result ->
      {_slot_id, ""} = Integer.parse(result["slot_id"])
    end)
  end

  test "YTS-trending video appears in trending tab with proper slots", %{conn: conn} do
    yts_id = "xYzAbC12345"
    Enum.each(1..150, fn _ -> Trending.record_view(yts_id) end)

    mock_piped_with_streams(%{
      "xYzAbC12345" => piped_stream_response(yts_id, "YTS Popular Video")
    })

    results = fetch_trending(conn)

    yts_entry = Enum.find(results, fn r -> r["youtube_id"] == yts_id end)
    assert yts_entry != nil
    assert yts_entry["title"] == "YTS Popular Video"
    assert yts_entry["type"] == "video"

    # Should have a valid slot pointing to the right youtube_id
    {slot_id, ""} = Integer.parse(yts_entry["slot_id"])
    slot = Slot.fetch_by_id(slot_id)
    assert slot != nil
    assert slot.youtube_id == yts_id
    assert slot.keepalive

    # Should also have a channel slot
    assert yts_entry["channel_slot"] != nil
  end

  test "YTS-trending video that also appears in upstream is not duplicated", %{conn: conn} do
    # HYzyRHAHJl8 is the first entry in the upstream trending fixture
    existing_id = "HYzyRHAHJl8"
    Enum.each(1..150, fn _ -> Trending.record_view(existing_id) end)

    mock_piped_with_streams()

    results = fetch_trending(conn)

    matching = Enum.filter(results, fn r -> r["youtube_id"] == existing_id end)
    assert length(matching) == 1
  end

  test "YTS video with failed metadata fetch is excluded from trending tab", %{conn: conn} do
    bad_id = "badVid123ab"
    Enum.each(1..150, fn _ -> Trending.record_view(bad_id) end)

    # mock_piped_with_streams with no stream mock for bad_id → returns 500
    mock_piped_with_streams()

    results = fetch_trending(conn)

    bad_entry = Enum.find(results, fn r -> r["youtube_id"] == bad_id end)
    assert bad_entry == nil

    # Upstream results should still be present
    assert length(results) > 0
  end

  test "YTS video below minimum view threshold is excluded", %{conn: conn} do
    low_id = "lowView12345"
    # Only 10 views — below the minimum threshold
    Enum.each(1..10, fn _ -> Trending.record_view(low_id) end)

    mock_piped_with_streams(%{
      "lowView12345" => piped_stream_response(low_id, "Low View Video")
    })

    results = fetch_trending(conn)

    low_entry = Enum.find(results, fn r -> r["youtube_id"] == low_id end)
    assert low_entry == nil
  end

  test "all trending results have keepalive set", %{conn: conn} do
    yts_id = "xYzAbC12345"
    Enum.each(1..150, fn _ -> Trending.record_view(yts_id) end)

    mock_piped_with_streams(%{
      "xYzAbC12345" => piped_stream_response(yts_id, "YTS Popular Video")
    })

    results = fetch_trending(conn)

    Enum.each(results, fn result ->
      case result["type"] do
        type when type in ["video", "livestream", "short"] ->
          {slot_id, ""} = Integer.parse(result["slot_id"])
          slot = Slot.fetch_by_id(slot_id)
          assert slot.keepalive, "slot #{slot_id} (#{result["youtube_id"]}) should be keepalive"

        _ ->
          :ok
      end
    end)
  end

  test "trending tab is cached and reuses same data on subsequent requests", %{conn: conn} do
    yts_id = "xYzAbC12345"
    Enum.each(1..150, fn _ -> Trending.record_view(yts_id) end)

    mock_piped_with_streams(%{
      "xYzAbC12345" => piped_stream_response(yts_id, "YTS Popular Video")
    })

    results1 = fetch_trending(conn)
    results2 = fetch_trending(conn)

    # Same results on second request (cached)
    assert results1 == results2
  end
end
