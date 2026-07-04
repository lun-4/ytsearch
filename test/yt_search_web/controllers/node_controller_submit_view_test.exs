defmodule YtSearchWeb.NodeControllerSubmitViewTest do
  @moduledoc """
  Tests for NodeController.submit_view — verifies that view submissions populate
  both the video_counter aggregate and the video_views event log.
  """
  use YtSearchWeb.ConnCase, async: false

  alias YtSearch.Data.TrendingRepo

  setup do
    TrendingRepo.query!("DELETE FROM video_counter")
    TrendingRepo.query!("DELETE FROM video_views")

    System.put_env("NODE_AUTH", "test-secret-token")

    on_exit(fn ->
      System.delete_env("NODE_AUTH")
    end)

    :ok
  end

  defp submit_view(conn, youtube_id) do
    conn
    |> put_req_header("authorization", "Bearer test-secret-token")
    |> put_req_header("content-type", "application/json")
    |> post("/api/node/view", %{"youtube_id" => youtube_id})
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

  defp event_count_for(youtube_id) do
    %{rows: [[count]]} =
      TrendingRepo.query!(
        "SELECT COUNT(*) FROM video_views WHERE yt_video_id = ?",
        [youtube_id]
      )

    count
  end

  test "single submission inserts a counter row and an event row", %{conn: conn} do
    resp = conn |> submit_view("vid_a") |> json_response(200)
    assert resp["status"] == "ok"

    assert counter_for("vid_a") == 1
    assert event_count_for("vid_a") == 1
  end

  test "repeated submissions increment counter and append events", %{conn: conn} do
    Enum.each(1..3, fn _ -> submit_view(conn, "vid_b") end)

    assert counter_for("vid_b") == 3
    assert event_count_for("vid_b") == 3
  end

  test "events have a viewed_at within the last few seconds", %{conn: conn} do
    submit_view(conn, "vid_c")

    %{rows: [[viewed_at_epoch]]} =
      TrendingRepo.query!(
        "SELECT unixepoch(viewed_at) FROM video_views WHERE yt_video_id = ?",
        ["vid_c"]
      )

    now = System.system_time(:second)
    assert is_integer(viewed_at_epoch)
    assert abs(now - viewed_at_epoch) < 5
  end

  test "missing youtube_id returns 400 and writes nothing", %{conn: conn} do
    resp =
      conn
      |> put_req_header("authorization", "Bearer test-secret-token")
      |> put_req_header("content-type", "application/json")
      |> post("/api/node/view", %{})
      |> json_response(400)

    assert resp["error"] == "missing youtube_id"

    %{rows: [[counter_n]]} = TrendingRepo.query!("SELECT COUNT(*) FROM video_counter")
    %{rows: [[events_n]]} = TrendingRepo.query!("SELECT COUNT(*) FROM video_views")
    assert counter_n == 0
    assert events_n == 0
  end
end
