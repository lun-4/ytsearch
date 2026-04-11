defmodule YtSearch.Trending do
  @moduledoc """
  Centralized access to YTS trending data (view counts).
  Works in both monolith mode (local TrendingRepo) and
  external mode (HTTP to trending node).
  """

  require Logger
  alias YtSearch.Data.TrendingRepo

  @doc """
  Record a video view event into TrendingRepo.
  """
  def record_view(youtube_id) do
    TrendingRepo.transaction(
      fn ->
        TrendingRepo.query!(
          """
          INSERT INTO video_counter (yt_video_id, view_count)
          VALUES (?, 1)
          ON CONFLICT(yt_video_id) DO UPDATE SET
            view_count = view_count + 1
          """,
          [youtube_id]
        )

        TrendingRepo.query!(
          """
          INSERT INTO video_views (yt_video_id, viewed_at)
          VALUES (?, datetime('now'))
          """,
          [youtube_id]
        )
      end,
      mode: :immediate
    )
  end

  @doc """
  Query top N videos by view count from local TrendingRepo.
  """
  def top_videos(limit \\ 10) do
    result =
      TrendingRepo.query!(
        "SELECT yt_video_id, view_count FROM video_counter ORDER BY view_count DESC LIMIT ?",
        [min(limit, 50)]
      )

    Enum.map(result.rows, fn [id, count] -> %{youtube_id: id, view_count: count} end)
  end

  @doc """
  Fetch top videos — local TrendingRepo or from external trending node.
  Returns {:ok, [%{youtube_id: ..., view_count: ...}]} or {:ok, []}.
  """
  def fetch_top_videos!(limit \\ 10) do
    case System.get_env("EXTERNAL_TRENDING_NODE") do
      url when is_binary(url) and url != "" ->
        fetch_top_videos_remote(url, limit)

      _ ->
        if GenServer.whereis(TrendingRepo) do
          {:ok, top_videos(limit)}
        else
          {:ok, []}
        end
    end
  end

  defp fetch_top_videos_remote(trending_url, limit) do
    url = "#{trending_url}/api/node/top_videos?limit=#{limit}"

    headers = [
      {"Authorization", "Bearer #{System.get_env("NODE_AUTH")}"}
    ]

    case HTTPoison.get(url, headers, timeout: 5000) do
      {:ok, %{status_code: 200, body: body}} ->
        %{"videos" => videos} = Jason.decode!(body)

        {:ok,
         Enum.map(videos, fn v ->
           %{youtube_id: v["youtube_id"], view_count: v["view_count"]}
         end)}

      {:ok, %{status_code: status, body: body}} ->
        Logger.warning("Trending node top_videos returned #{status}: #{body}")
        {:ok, []}

      {:error, reason} ->
        Logger.warning("Failed to fetch top_videos from trending node: #{inspect(reason)}")
        {:ok, []}
    end
  end
end
