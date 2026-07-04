defmodule YtSearch.Trending.Reporter do
  @moduledoc """
  Periodic reporting of top trending videos (runs every 3h).

  1. Query top 10 most-viewed videos from video_counter
  2. Log them and send to Discord webhook
  3. Prune view events older than 48h from video_views
  4. Rebuild video_counter from remaining events (rolling 48h window)
  """

  require Logger

  def tick() do
    Logger.info("Trending Reporter: Generating report...")

    # Query top 10 videos by view count
    result =
      YtSearch.Data.TrendingRepo.query!("""
        SELECT yt_video_id, view_count
        FROM video_counter
        ORDER BY view_count DESC
        LIMIT 10
      """)

    # Log and send to Discord
    if result.num_rows > 0 do
      Logger.info("Top 10 Trending Videos:")

      result.rows
      |> Enum.with_index(1)
      |> Enum.each(fn {[yt_video_id, view_count], rank} ->
        Logger.info("  #{rank}. #{yt_video_id} - #{view_count} views")
      end)

      # Send to Discord webhook if configured
      send_discord_webhook(result.rows)
    else
      Logger.info("No videos tracked...")
    end

    # Prune view events older than 48h
    YtSearch.Data.TrendingRepo.query!("""
      DELETE FROM video_views WHERE unixepoch(viewed_at) < (unixepoch() - 48 * 3600)
    """)

    # Rebuild video_counter from remaining events
    rebuild_video_counter()

    Logger.info("Trending Reporter: Pruned views older than 48h and rebuilt video_counter")
  end

  defp rebuild_video_counter do
    YtSearch.Data.TrendingRepo.query!("DELETE FROM video_counter")

    {:ok, counts} =
      YtSearch.Data.TrendingRepo.transaction(fn ->
        Ecto.Adapters.SQL.stream(
          YtSearch.Data.TrendingRepo,
          "SELECT yt_video_id FROM video_views"
        )
        |> Enum.reduce(%{}, fn %{rows: rows}, acc ->
          Enum.reduce(rows, acc, fn [yt_video_id], inner_acc ->
            Map.update(inner_acc, yt_video_id, 1, &(&1 + 1))
          end)
        end)
      end)

    Enum.each(counts, fn {yt_video_id, view_count} ->
      YtSearch.Data.TrendingRepo.query!("""
        INSERT INTO video_counter (yt_video_id, view_count)
        VALUES (?, ?)
      """, [yt_video_id, view_count])
    end)
  end

  defp send_discord_webhook(trending_videos) do
    case System.get_env("TRENDING_REPORTER_WEBHOOK_URL") do
      nil ->
        Logger.debug("TRENDING_REPORTER_WEBHOOK_URL not set, skipping Discord notification")

      "" ->
        Logger.debug("TRENDING_REPORTER_WEBHOOK_URL is empty, skipping Discord notification")

      webhook_url ->
        # Format trending videos as markdown list
        video_list =
          trending_videos
          |> Enum.with_index(1)
          |> Enum.map(fn {[yt_video_id, view_count], rank} ->
            "#{rank}. [#{yt_video_id}](https://youtube.com/watch?v=#{yt_video_id}) - #{view_count} views"
          end)
          |> Enum.join("\n")

        content = "**Top 10 Trending Videos**\n#{video_list}"

        payload = %{content: content}
        headers = [{"Content-Type", "application/json"}]
        body = Jason.encode!(payload)

        case HTTPoison.post(webhook_url, body, headers) do
          {:ok, %HTTPoison.Response{status_code: status}} when status in 200..299 ->
            Logger.info("Successfully sent trending report to Discord")

          {:ok, %HTTPoison.Response{status_code: status, body: response_body}} ->
            Logger.warning("Discord webhook returned status #{status}: #{response_body}")

          {:error, %HTTPoison.Error{reason: reason}} ->
            Logger.error("Failed to send Discord webhook: #{inspect(reason)}")
        end
    end
  end
end
