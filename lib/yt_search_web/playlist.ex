defmodule YtSearchWeb.Playlist do
  alias YtSearch.Youtube
  require Logger

  def from_ytdlp_data(youtube_json_results) do
    youtube_json_results
    |> Enum.map(fn ytdlp_data ->
      entity_type =
        case ytdlp_data["ie_key"] do
          "YoutubeTab" ->
            if String.contains?(ytdlp_data["url"], "/playlist?") do
              :playlist
            else
              :channel
            end

          "Youtube" ->
            if String.contains?(ytdlp_data["url"], "/shorts/") do
              :short
            else
              if ytdlp_data["live_status"] == "is_live" do
                :livestream
              else
                :video
              end
            end

          nil ->
            # this is a fallback for the trending tab
            :channel
        end

      ytdlp_data =
        case ytdlp_data["ie_key"] do
          nil ->
            # infer some data when ie_key is nil
            # happens on trending tab
            url = ytdlp_data["url"] |> URI.parse()
            channel_id = url.path |> Path.basename()

            ytdlp_data
            |> Map.put("id", channel_id)

          _other ->
            ytdlp_data
        end

      {entity_type, ytdlp_data}
    end)
    |> Enum.map(fn {entity_type, ytdlp_data} ->
      thumbnail_metadata = Youtube.Thumbnail.fetch_in_background(entity_type, ytdlp_data)

      youtube_id = ytdlp_data["id"]

      Logger.debug("processing for ytid #{youtube_id}")

      Mutex.under(PlaylistEntryCreatorMutex, "#{entity_type}:#{youtube_id}", fn ->
        do_create_playlist_entry(entity_type, ytdlp_data, thumbnail_metadata, youtube_id)
      end)
    end)
  end

  defp do_create_playlist_entry(entity_type, ytdlp_data, thumbnail_metadata, youtube_id) do
    case entity_type do
      t when t in [:video, :short, :livestream, :playlist] ->
        slot =
          case t do
            :playlist ->
              YtSearch.PlaylistSlot.from(youtube_id)

            _ ->
              YtSearch.Slot.create(youtube_id, ytdlp_data["duration"])
          end

        # when using /channel/videos, channel_id is null, so
        # fallback to playlist_uploader_id in these cases
        channel_id = ytdlp_data["channel_id"] || ytdlp_data["playlist_uploader_id"]

        channel_slot =
          case entity_type do
            t when t in [:video, :livestream] ->
              # full videos should provide channel metadata
              # from/1 will crash if its nil
              YtSearch.ChannelSlot.from(channel_id)

            t when t in [:short, :playlist] ->
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
          youtube_id: youtube_id,
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
          view_count:
            if entity_type == :livestream do
              ytdlp_data["concurrent_view_count"]
            else
              ytdlp_data["view_count"]
            end,
          thumbnail: thumbnail_metadata,
          slot_id: "#{slot.id}"
        }

      :channel ->
        slot = YtSearch.ChannelSlot.from(youtube_id)

        %{
          type: :channel,
          title: ytdlp_data["title"],
          youtube_id: youtube_id,
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
        raise "invalid type: #{entity_type}"
    end
  end
end
