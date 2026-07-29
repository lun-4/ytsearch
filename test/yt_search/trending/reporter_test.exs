defmodule YtSearch.Trending.ReporterTest do
  @moduledoc """
  Tests for Trending.Reporter.tick — verifies that the rebuild of video_counter
  from the video_views event log produces correct per-video counts (Task 7).
  """
  use YtSearchWeb.ConnCase, async: false

  alias YtSearch.Data.TrendingRepo
  alias YtSearch.Trending.Reporter

  setup do
    TrendingRepo.query!("DELETE FROM video_counter")
    TrendingRepo.query!("DELETE FROM video_views")
    :ok
  end

  defp insert_views(youtube_id, n) do
    Enum.each(1..n, fn _ ->
      TrendingRepo.query!(
        "INSERT INTO video_views (yt_video_id, viewed_at) VALUES (?, datetime('now'))",
        [youtube_id]
      )
    end)
  end

  defp counter_for(youtube_id) do
    case TrendingRepo.query!(
           "SELECT view_count FROM video_counter WHERE yt_video_id = ?",
           [youtube_id]
         ) do
      %{rows: [[count]]} -> count
      %{rows: []} -> nil
    end
  end

  test "tick rebuilds video_counter from recent view events" do
    insert_views("vid_a", 5)
    insert_views("vid_b", 2)
    insert_views("vid_c", 1)

    # a stale counter row that no longer reflects the events must be overwritten
    TrendingRepo.query!(
      "INSERT INTO video_counter (yt_video_id, view_count) VALUES (?, ?)",
      ["vid_a", 999]
    )

    # a counter row for a video with no remaining events must be dropped
    TrendingRepo.query!(
      "INSERT INTO video_counter (yt_video_id, view_count) VALUES (?, ?)",
      ["vid_gone", 42]
    )

    Reporter.tick()

    assert counter_for("vid_a") == 5
    assert counter_for("vid_b") == 2
    assert counter_for("vid_c") == 1
    assert counter_for("vid_gone") == nil

    %{rows: [[total_rows]]} = TrendingRepo.query!("SELECT COUNT(*) FROM video_counter")
    assert total_rows == 3
  end

  test "tick on an empty view log leaves an empty counter" do
    Reporter.tick()

    %{rows: [[total_rows]]} = TrendingRepo.query!("SELECT COUNT(*) FROM video_counter")
    assert total_rows == 0
  end
end
