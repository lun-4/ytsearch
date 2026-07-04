defmodule YtSearch.Trending.Mixer do
  @moduledoc """
  Mixes upstream YouTube trending data with YTS community-trending videos.

  Strategy: "reserve slots" — top K YTS-trending videos get guaranteed slots
  in the trending tab, the rest are filled by upstream, then shuffled.
  """

  require Logger
  alias YtSearch.Youtube

  @keys_to_copy [
    "title",
    "uploader",
    "uploaderUrl",
    "isShort",
    "duration",
    "views",
    {"uploader", "uploaderName"},
    {"description", "shortDescription"},
    {"thumbnailUrl", "thumbnail"}
  ]

  @yts_slots 15
  @min_views 100
  @metadata_concurrency 5
  @metadata_timeout 5_000

  @doc """
  Returns a mixed trending list in Piped stream format.
  Falls back to upstream-only if YTS data is unavailable or empty.

  Returns {:ok, list_of_piped_maps} | {:ok, nil}
  """
  def mixed_trending do
    case Youtube.trending() do
      {:ok, upstream} when is_list(upstream) ->
        yts_entries = fetch_and_resolve_yts_videos(upstream)

        if yts_entries == [] do
          {:ok, upstream}
        else
          mixed = (yts_entries ++ upstream) |> Enum.shuffle()
          {:ok, mixed}
        end

      v ->
        Logger.warning("upstream trending returned incorrect result: #{inspect(v)}")
        v
    end
  end

  defp fetch_and_resolve_yts_videos(upstream) do
    # Fetch candidate count larger than @yts_slots to account for
    # dedup and metadata fetch failures
    candidate_count = @yts_slots * 3

    {:ok, yts_videos} = YtSearch.Trending.fetch_top_videos!(candidate_count)
    upstream_ids = upstream_youtube_ids(upstream)

    filtered = Enum.filter(yts_videos, fn %{view_count: count} -> count >= @min_views end)
    deduped = Enum.reject(filtered, fn %{youtube_id: id} -> MapSet.member?(upstream_ids, id) end)

    deduped
    |> Enum.take(@yts_slots * 2)
    |> resolve_metadata()
    |> Enum.take(@yts_slots)
  end

  defp upstream_youtube_ids(upstream) do
    upstream
    |> Enum.map(fn entry ->
      case entry["url"] do
        "/watch?v=" <> id -> id
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  defp resolve_metadata(candidates) do
    candidates
    |> Task.async_stream(
      fn %{youtube_id: youtube_id} ->
        case Youtube.video_metadata(youtube_id) do
          {:ok, piped_response} ->
            {:ok, metadata_to_stream_format(youtube_id, piped_response)}

          error ->
            Logger.debug(
              "Failed to fetch metadata for YTS trending video #{youtube_id}: #{inspect(error)}"
            )

            :error
        end
      end,
      max_concurrency: @metadata_concurrency,
      timeout: @metadata_timeout,
      on_timeout: :kill_task
    )
    |> Enum.flat_map(fn
      {:ok, {:ok, entry}} -> [entry]
      _ -> []
    end)
  end

  defp metadata_to_stream_format(youtube_id, piped_response) do
    raw_upload_date = piped_response["uploadDate"]

    @keys_to_copy
    |> Enum.reduce(%{}, fn key, result ->
      {key_from, key_to} =
        case key do
          {_, _} -> key
          key -> {key, key}
        end

      Map.put(result, key_to, piped_response[key_from])
    end)
    |> Map.put("type", "stream")
    |> Map.put("url", "/watch?v=#{youtube_id}")
    |> Map.put("uploaded", parse_upload_date(raw_upload_date))
  end

  defp parse_upload_date(nil), do: nil

  defp parse_upload_date(raw_upload_date) do
    if String.contains?(raw_upload_date, "T") do
      {:ok, dt, _tz} = DateTime.from_iso8601(raw_upload_date)
      DateTime.to_unix(dt, :millisecond)
    else
      raw_upload_date
      |> Date.from_iso8601!()
      |> DateTime.new!(~T[00:00:00])
      |> DateTime.to_unix(:millisecond)
    end
  end
end
