defmodule YtSearchWeb.Playlist do
  alias YtSearch.Youtube

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

      case entity_type do
        :video ->
          slot = YtSearch.Slot.from(ytdlp_data["id"])

          %{
            type: entity_type,
            title: ytdlp_data["title"],
            youtube_id: ytdlp_data["id"],
            youtube_url: ytdlp_data["url"],
            duration: ytdlp_data["duration"],
            channel_name: ytdlp_data["channel"],
            description: ytdlp_data["description"],
            uploaded_at: ytdlp_data["timestamp"],
            view_count: ytdlp_data["view_count"],
            thumbnail: thumbnail_metadata,
            slot_id: "#{slot.id}"
          }

        :short ->
          slot = YtSearch.Slot.from(ytdlp_data["id"])

          %{
            type: entity_type,
            title: ytdlp_data["title"],
            youtube_id: ytdlp_data["id"],
            youtube_url: ytdlp_data["url"],
            duration: ytdlp_data["duration"],
            channel_name: ytdlp_data["channel"],
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
            slot_id: "#{slot.id}"
          }

        _ ->
          raise "invalid type"
      end
    end)
  end
end
