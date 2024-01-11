defmodule YtSearchWeb.Playlist do
  alias YtSearch.Youtube
  require Logger

  def from_piped_data(json, opts \\ []) do
    json
    |> Enum.map(fn entry ->
      entity_type =
        case entry["type"] do
          "stream" ->
            cond do
              entry["isShort"] -> :short
              entry["duration"] in [-1, 0] -> :livestream
              entry["views"] == -1 -> :upcoming
              true -> :video
            end

          "playlist" ->
            :playlist

          "channel" ->
            :channel
        end

      {entity_type, entry}
    end)
    |> Enum.filter(fn {entity_type, data} ->
      cond do
        # topic channels don't provide a videos tab, ignore them
        entity_type == :channel and String.ends_with?(data["name"] || "", " - Topic") -> false
        # we don't support upcoming things that don't actually have any videos for
        entity_type == :upcoming -> false
        true -> true
      end
    end)
    |> Enum.map(fn {entity_type, data} ->
      youtube_id = data["url"] |> youtube_id_from_url
      thumbnail_metadata = Youtube.Thumbnail.fetch_piped_in_background(youtube_id, data, opts)

      Logger.debug("processing for ytid #{youtube_id}")

      Mutex.under(PlaylistEntryCreatorMutex, "#{entity_type}:#{youtube_id}", fn ->
        do_create_playlist_entry_piped(entity_type, data, thumbnail_metadata, youtube_id, opts)
      end)
    end)
  end

  defp youtube_id_from_url(url) do
    cond do
      url == nil ->
        raise "nil url"

      String.starts_with?(url, "/watch") ->
        url |> String.split("=") |> Enum.at(1)

      String.starts_with?(url, "/channel") ->
        url |> String.split("/") |> Enum.at(2)

      String.starts_with?(url, "/playlist") ->
        url |> String.split("=") |> Enum.at(1)

      true ->
        raise "unsupported url: #{url}"
    end
  end

  defp do_create_playlist_entry_piped(entity_type, data, thumbnail_metadata, youtube_id, opts) do
    case entity_type do
      t when t in [:video, :short, :livestream, :playlist] ->
        slot =
          case t do
            :playlist ->
              YtSearch.PlaylistSlot.create(youtube_id, opts)

            _ ->
              YtSearch.Slot.create(
                youtube_id,
                data["duration"],
                opts |> Keyword.put(:entity_type, entity_type)
              )
          end

        channel_id =
          unless data["uploaderUrl"] == nil do
            data["uploaderUrl"] |> youtube_id_from_url
          else
            nil
          end

        channel_slot =
          case entity_type do
            t when t in [:video, :livestream] ->
              # full videos should provide channel metadata
              if channel_id != nil do
                YtSearch.ChannelSlot.create(channel_id, opts)
              else
                nil
              end

            t when t in [:short, :playlist] ->
              # shorts dont give proper metadata about themselves at all
              # fuck shorts
              # make it optional
              if channel_id != nil do
                YtSearch.ChannelSlot.create(channel_id, opts)
              else
                nil
              end
          end

        channel_name = data["uploaderName"]

        %{
          type: entity_type,
          title: data["title"] || data["name"],
          youtube_id: youtube_id,
          duration: data["duration"],
          channel_name: channel_name,
          channel_slot:
            unless channel_slot == nil do
              "#{channel_slot.id}"
            else
              nil
            end,
          description: data["shortDescription"],
          uploaded_at:
            unless data["uploaded"] == nil do
              div(data["uploaded"], 1000)
            else
              nil
            end,
          view_count: data["views"],
          thumbnail: thumbnail_metadata,
          slot_id: "#{slot.id}"
        }

      :channel ->
        slot = YtSearch.ChannelSlot.create(youtube_id, opts)

        %{
          type: :channel,
          title: data["name"],
          youtube_id: youtube_id,
          channel_name: data["name"],
          description: data["description"],
          subscriber_count: data["subscribers"],
          thumbnail: thumbnail_metadata,
          channel_slot: "#{slot.id}",
          slot_id: "#{slot.id}"
        }

      _ ->
        raise "invalid type: #{entity_type}"
    end
  end
end
