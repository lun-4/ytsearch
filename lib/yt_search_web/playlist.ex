defmodule YtSearchWeb.Playlist do
  alias YtSearch.Youtube
  require Logger

  def from_ytdlp_data(youtube_json_results) do
    youtube_json_results
    |> Enum.map(fn ytdlp_data ->
      entity_type =
        case ytdlp_data["ie_key"] do
          "YoutubeTab" ->
            :channel

          "Youtube" ->
            if String.contains?(ytdlp_data["url"], "/shorts/") do
              :short
            else
              :video
            end
        end

      {entity_type, ytdlp_data}
    end)
    |> Enum.map(fn {entity_type, ytdlp_data} ->
      thumbnail_metadata = Youtube.Thumbnail.fetch_in_background(ytdlp_data)

      Logger.debug("parsing #{inspect(ytdlp_data)}")

      case entity_type do
        t when t == :video or t == :short ->
          slot = YtSearch.Slot.from(ytdlp_data["id"])

          # when using /channel/videos, channel_id is null, so
          # fallback to playlist_uploader_id in these cases
          channel_id = ytdlp_data["channel_id"] || ytdlp_data["playlist_uploader_id"]

          channel_slot =
            case entity_type do
              :video ->
                # full videos should provide channel metadata
                # from/1 will crash if its nil
                YtSearch.ChannelSlot.from(channel_id)

              :short ->
                # shorts dont give proper metadata about themselves at all
                # fuck shorts
                # make it optional
                if channel_id == nil do
                  nil
                else
                  YtSearch.ChannelSlot.from(channel_id)
                end
            end

          channel_name = ytdlp_data["channel"] || ytdlp_data["playlist_uploader"]

          %{
            type: entity_type,
            title: ytdlp_data["title"],
            youtube_id: ytdlp_data["id"],
            youtube_url: ytdlp_data["url"],
            duration: ytdlp_data["duration"],
            channel_name: channel_name,
            channel_slot:
              if channel_slot != nil do
                "#{channel_slot.id}"
              else
                nil
              end,
            description: ytdlp_data["description"],
            uploaded_at: ytdlp_data["timestamp"],
            view_count: ytdlp_data["view_count"],
            thumbnail: thumbnail_metadata,
            slot_id: "#{slot.id}"
          }

        :channel ->
          slot = YtSearch.ChannelSlot.from(ytdlp_data["id"])

          %{
            type: :channel,
            title: ytdlp_data["title"],
            youtube_id: ytdlp_data["id"],
            youtube_url: ytdlp_data["url"],
            duration: ytdlp_data["duration"],
            channel_name: ytdlp_data["channel"],
            description: ytdlp_data["description"],
            uploaded_at: ytdlp_data["timestamp"],
            view_count: ytdlp_data["view_count"],
            thumbnail: thumbnail_metadata,
            channel_slot: "#{slot.id}",
            slot_id: "#{slot.id}"
          }

        _ ->
          raise "invalid type"
      end
    end)
  end
end
