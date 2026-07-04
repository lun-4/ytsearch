defmodule YtSearchWeb.Playlist do
  alias YtSearch.Youtube
  require Logger

  def from_piped_data(json, opts \\ []) do
    nextpage? = opts |> Keyword.get(:nextpage?, false)
    transform_upcoming_videos? = opts |> Keyword.get(:transform_upcoming_videos?, false)

    nextpage_data =
      if nextpage? do
        json.nextpage
      else
        nil
      end

    thumbnail_limit =
      Application.get_env(:yt_search, YtSearch.Constants)[:thumbnails_in_search_page]

    if nextpage? do
      json.results
    else
      json
    end
    |> Enum.map(fn entry ->
      entity_type =
        case entry["type"] do
          "stream" ->
            cond do
              entry["isShort"] ->
                :short

              entry["duration"] in [-1, 0] ->
                :livestream

              entry["views"] == -1 ->
                if transform_upcoming_videos? do
                  # for the mixed trending tab, videos from the Music and Movie tabs
                  # return views=-1 (Gaming doesn't, for some fucked up reason).
                  #
                  # let Trending (and only Trending) bypass this behavior
                  # and promote upcoming videos to real videos.
                  :video
                else
                  :upcoming
                end

              true ->
                :video
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
    |> Enum.with_index()
    |> Enum.map(fn {{entity_type, data}, index} ->
      youtube_id = data["url"] |> youtube_id_from_url

      thumbnail_metadata =
        if index < thumbnail_limit do
          Youtube.Thumbnail.fetch_piped_in_background(youtube_id, data, opts)
        else
          %YtSearch.Youtube.Thumbnail.ThumbnailMetadata{
            aspect_ratio: 1.77
          }
        end

      Logger.debug("processing for ytid #{youtube_id}")

      Mutex.under(PlaylistEntryCreatorMutex, "#{entity_type}:#{youtube_id}", fn ->
        do_create_playlist_entry_piped(entity_type, data, thumbnail_metadata, youtube_id, opts)
      end)
    end)
    |> then(fn result_list ->
      if nextpage? do
        %{results: result_list, nextpage: nextpage_data, type: json.type, title: json.title}
      else
        result_list
      end
    end)
  end

  defp youtube_id_from_url(url) do
    cond do
      url == nil ->
        raise "nil url"

      String.starts_with?(url, "/watch") ->
        %URI{query: query} = URI.parse(url)
        URI.decode_query(query || "")["v"]

      String.starts_with?(url, "/channel") ->
        %URI{path: path} = URI.parse(url)
        path |> String.split("/") |> Enum.at(2)

      String.starts_with?(url, "/playlist") ->
        %URI{query: query} = URI.parse(url)
        URI.decode_query(query || "")["list"]

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
                opts |> Keyword.put(:entity_type, entity_type) |> Keyword.put(:type, entity_type)
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
