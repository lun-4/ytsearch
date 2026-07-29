defmodule YtSearchWeb.HelloController do
  use YtSearchWeb, :controller
  require Logger
  alias YtSearch.Data.ThumbnailRepo
  alias YtSearch.SlotUtilities
  alias YtSearch.SearchSlot
  alias YtSearch.Trending.Mixer
  alias YtSearch.Youtube
  alias YtSearchWeb.Playlist
  alias YtSearch.CounterServer

  def hello(conn, params) do
    __MODULE__.BuildReporter.increment(params["build_number"] || "<unknown>")
    render_hello(conn, fetch_trending_tab())
  end

  def hello_staging(conn, params) do
    __MODULE__.BuildReporter.increment(params["build_number"] || "<unknown>")
    render_hello(conn, fetch_staging_trending_tab())
  end

  defp render_hello(conn, trending_tab) do
    counter_value = CounterServer.get_value()

    accept_header =
      case Plug.Conn.get_req_header(conn, "accept") do
        [] -> nil
        [value | _] -> value
      end

    client_sends_accept_header = accept_header == "*/*"

    conn
    |> json(%{
      online: true,
      trending_tab: trending_tab,
      counter_data: counter_value,
      client_sends_accept_header: client_sends_accept_header
    })
  end

  def fetch_trending_tab(v \\ nil) do
    case v || Cachex.get(:tabs, "trending") do
      {:ok, nil} ->
        if v != nil do
          raise "should not re-request on given do_fetch value"
        else
          fetch_trending_tab(do_fetch_trending_tab())
        end

      {:ok, :nothing} ->
        nil

      {:ok, data} ->
        data

      value ->
        Logger.error("trending tab fetch failed: #{inspect(value)}")
        nil
    end
  end

  def fetch_staging_trending_tab(v \\ nil) do
    case v || Cachex.get(:tabs, "staging_trending") do
      {:ok, nil} ->
        if v != nil do
          raise "should not re-request on given do_fetch value"
        else
          fetch_staging_trending_tab(do_fetch_staging_trending_tab())
        end

      {:ok, :nothing} ->
        nil

      {:ok, data} ->
        data

      value ->
        Logger.error("staging trending tab fetch failed: #{inspect(value)}")
        nil
    end
  end

  import Ecto.Query

  defp keepalived_slots do
    [YtSearch.Slot, YtSearch.ChannelSlot]
    |> Enum.map(fn module ->
      from(s in module, select: s, where: s.keepalive)
      |> SlotUtilities.repo(module).replica().all()
    end)
    |> List.flatten()
  end

  defp upstream_trending_tab do
    case Youtube.trending() do
      {:ok, data} when is_list(data) ->
        results =
          data
          |> Playlist.from_piped_data(keepalive: true, transform_upcoming_videos?: true)

        search_slot =
          results
          |> SearchSlot.from_playlist("yt://trending", keepalive: true)

        YtSearchWeb.SearchController.broadcast_sync(search_slot)

        {:ok, %{search_results: results, slot_id: "#{search_slot.id}"}}

      v ->
        Logger.warning("upstream trending failed: #{inspect(v)}")
        {:ok, nil}
    end
  end

  defp unkeepalive_thumbnails(old_keepalived_slots) do
    # thumbnails follow different logic from slots, unkeepalive them prematurely
    # (slots are more important to keep alive mid-trending-tab-refresh than thumbs)

    youtube_ids = old_keepalived_slots |> Enum.map(fn slot -> slot.youtube_id end)

    # If external thumbnailer is configured, send unkeepalive to thumbnailer
    if System.get_env("EXTERNAL_THUMBNAIL_NODE") do
      YtSearch.ThumbnailerClient.unkeepalive_thumbnails(youtube_ids)
    else
      # Local unkeepalive
      youtube_ids
      |> Enum.chunk_every(500)
      |> Enum.each(fn chunk ->
        from(s in YtSearch.Thumbnail, where: s.id in ^chunk)
        |> ThumbnailRepo.update_all(set: [keepalive: false])
      end)
    end
  end

  defp do_fetch_trending_tab() do
    url = "https://www.youtube.com/feed/trending"

    Mutex.under(SearchMutex, url, fn ->
      case Cachex.get(:tabs, "trending") do
        {:ok, nil} ->
          # we need to transition the old slots from the previous iteration of the trending tab
          # into an unkeepalived state so that we don't keep them in the pool forever.

          # to do that we need to have
          # - the old set of slots (A)
          # - the new set of slots (B)
          #
          # and remove keepalive from slots that are in C = A-B
          # (slots that are in A but not in B)

          old_keepalived_slots = keepalived_slots()
          unkeepalive_thumbnails(old_keepalived_slots)
          {:ok, data} = upstream_trending_tab()

          cached_data =
            if data == nil do
              :nothing
            else
              data
            end

          Cachex.put(
            :tabs,
            "trending",
            cached_data,
            # 2 hours
            ttl: 2 * 60 * 60 * 1000
          )

          unless data == nil do
            # to calculate if a given slot from A is in B we build three sets out
            # of the new trending tab (B):
            # - video_ids: video slot_id strings
            # - channel_ids: channel_slot strings (a video entry refers to its channel slot)
            # - playlist_pairs: {slot_id, youtube_id} pairs for playlist entries
            #
            # the reduce keeps the exact same three clause shapes/guards as the old
            # nested Enum.map, with NO catch-all, so an unknown entry shape still crashes.
            {video_ids, channel_ids, playlist_pairs} =
              data.search_results
              |> Enum.reduce({MapSet.new(), MapSet.new(), MapSet.new()}, fn
                %{
                  type: video_type,
                  slot_id: slot_id_str,
                  channel_slot: channel_slot_id
                },
                {videos, channels, playlists}
                when video_type in [:video, :livestream, :short] and is_bitstring(slot_id_str) and
                       is_bitstring(channel_slot_id) ->
                  # this entry contributes both its video slot and its inner channel slot
                  {MapSet.put(videos, slot_id_str), MapSet.put(channels, channel_slot_id),
                   playlists}

                %{
                  type: video_type,
                  slot_id: slot_id_str,
                  channel_slot: nil
                },
                {videos, channels, playlists}
                when video_type in [:video, :livestream, :short] and is_bitstring(slot_id_str) ->
                  {MapSet.put(videos, slot_id_str), channels, playlists}

                # i forgot if playlists exist in the trending tab
                %{type: :playlist, slot_id: slot_id_str, youtube_id: youtube_id},
                {videos, channels, playlists}
                when is_bitstring(slot_id_str) ->
                  {videos, channels, MapSet.put(playlists, {slot_id_str, youtube_id})}
              end)

            # old slots not present in the new trending tab (C = A - B) are safe to
            # unkeepalive. one bulk write per module.
            now = SlotUtilities.generate_unix_timestamp()

            old_keepalived_slots
            |> Enum.reject(fn slot ->
              %module{} = slot

              case module do
                YtSearch.Slot ->
                  MapSet.member?(video_ids, "#{slot.id}")

                YtSearch.ChannelSlot ->
                  MapSet.member?(channel_ids, "#{slot.id}")

                YtSearch.PlaylistSlot ->
                  MapSet.member?(playlist_pairs, {"#{slot.id}", slot.youtube_id})
              end
            end)
            |> Enum.group_by(fn %module{} -> module end)
            |> Enum.each(fn {module, slots} ->
              ids = slots |> Enum.map(fn slot -> slot.id end)

              # updated_at set explicitly since update_all bypasses timestamp autogen
              # (the old changeset path bumped it)
              from(s in module, where: s.id in ^ids)
              |> SlotUtilities.repo(module).update_all(set: [keepalive: false, updated_at: now])
            end)
          end

          {:ok, data}

        v ->
          v
      end
    end)
  end

  defp upstream_staging_trending_tab do
    case Mixer.mixed_trending() do
      {:ok, data} when is_list(data) ->
        results =
          data
          |> Playlist.from_piped_data(keepalive: true, transform_upcoming_videos?: true)

        search_slot =
          results
          |> SearchSlot.from_playlist("yt://trending-staging", keepalive: true)

        YtSearchWeb.SearchController.broadcast_sync(search_slot)

        {:ok, %{search_results: results, slot_id: "#{search_slot.id}"}}

      v ->
        Logger.warning("staging mixed trending failed: #{inspect(v)}")
        {:ok, nil}
    end
  end

  # Staging-only trending fetch. Intentionally does NOT run the
  # keepalived-slot cleanup dance that do_fetch_trending_tab/0 does — it is
  # purely additive. See plan: staging slots are keepalive:true and will be
  # unkeepalived on the next prod fetch (~2h), which is accepted for the
  # dogfood test.
  defp do_fetch_staging_trending_tab() do
    Mutex.under(SearchMutex, "staging_trending", fn ->
      case Cachex.get(:tabs, "staging_trending") do
        {:ok, nil} ->
          {:ok, data} = upstream_staging_trending_tab()

          cached_data =
            if data == nil do
              :nothing
            else
              data
            end

          Cachex.put(
            :tabs,
            "staging_trending",
            cached_data,
            # 2 hours
            ttl: 2 * 60 * 60 * 1000
          )

          {:ok, data}

        v ->
          v
      end
    end)
  end

  defmodule BuildReporter do
    use Prometheus.Metric

    def setup() do
      Counter.declare(
        name: :yts_hello,
        help: "hello heartbeat world tags",
        labels: [:build_tag]
      )
    end

    def increment(build_tag) do
      Counter.inc(
        name: :yts_hello,
        labels: [build_tag]
      )
    end
  end
end
