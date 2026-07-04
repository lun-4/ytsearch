defmodule YtSearch.Trending.MixerTest do
  use YtSearchWeb.ConnCase, async: false

  alias YtSearch.Data.TrendingRepo
  alias YtSearch.Trending

  setup do
    YtSearch.Test.Data.default_global_mock()
    TrendingRepo.query!("DELETE FROM video_counter")
    TrendingRepo.query!("DELETE FROM video_views")
    :ok
  end

  describe "Trending.record_view/1" do
    test "inserts counter and event on first view" do
      Trending.record_view("test_vid_1")

      %{rows: [[count]]} =
        TrendingRepo.query!(
          "SELECT view_count FROM video_counter WHERE yt_video_id = ?",
          ["test_vid_1"]
        )

      assert count == 1

      %{rows: [[event_count]]} =
        TrendingRepo.query!(
          "SELECT COUNT(*) FROM video_views WHERE yt_video_id = ?",
          ["test_vid_1"]
        )

      assert event_count == 1
    end

    test "increments counter on repeated views" do
      Enum.each(1..5, fn _ -> Trending.record_view("test_vid_2") end)

      %{rows: [[count]]} =
        TrendingRepo.query!(
          "SELECT view_count FROM video_counter WHERE yt_video_id = ?",
          ["test_vid_2"]
        )

      assert count == 5

      %{rows: [[event_count]]} =
        TrendingRepo.query!(
          "SELECT COUNT(*) FROM video_views WHERE yt_video_id = ?",
          ["test_vid_2"]
        )

      assert event_count == 5
    end
  end

  describe "YtSearch.Trending.top_videos/1" do
    test "returns videos sorted by view count descending" do
      Trending.record_view("low_vid")
      Enum.each(1..10, fn _ -> Trending.record_view("high_vid") end)
      Enum.each(1..5, fn _ -> Trending.record_view("mid_vid") end)

      top = YtSearch.Trending.top_videos(3)
      assert length(top) == 3
      assert Enum.at(top, 0).youtube_id == "high_vid"
      assert Enum.at(top, 0).view_count == 10
      assert Enum.at(top, 1).youtube_id == "mid_vid"
      assert Enum.at(top, 1).view_count == 5
      assert Enum.at(top, 2).youtube_id == "low_vid"
      assert Enum.at(top, 2).view_count == 1
    end

    test "respects limit" do
      Enum.each(1..5, fn i ->
        Trending.record_view("vid_#{i}")
      end)

      assert length(YtSearch.Trending.top_videos(2)) == 2
    end

    test "returns empty list when no views" do
      assert YtSearch.Trending.top_videos() == []
    end
  end
end
