defmodule YtSearch.Trending.Reporter do
  @moduledoc """
  Periodic reporting of top trending videos from video_counter table.

  1. Query top 10 most-viewed videos
  2. Log them and send to Discord webhook
  3. Clear the video_counter table
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

    YtSearch.Data.TrendingRepo.query!("DELETE FROM video_counter")

    Logger.info("Trending Reporter: Cleared video_counter table")
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
