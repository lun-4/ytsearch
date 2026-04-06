defmodule YtSearchWeb.HelloController do
  use YtSearchWeb, :controller
  require Logger
  alias YtSearch.Data.ThumbnailRepo
  alias YtSearch.SlotUtilities
  alias YtSearch.SearchSlot
  alias YtSearch.Youtube
  alias YtSearchWeb.Playlist
  alias YtSearch.CounterServer

  def hello(conn, params) do
    __MODULE__.BuildReporter.increment(params["build_number"] || "<unknown>")
    trending_tab = fetch_trending_tab()
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
      {:ok, data} ->
        results =
          data
          |> Playlist.from_piped_data(keepalive: true, transform_upcoming_videos?: true)

        search_slot =
          results
          |> SearchSlot.from_playlist("yt://trending", keepalive: true)

        YtSearchWeb.SearchController.broadcast_sync(search_slot)

        {:ok, %{search_results: results, slot_id: "#{search_slot.id}"}}

      v ->
        Logger.warning("yt trending failed: #{inspect(v)}")
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
      |> Enum.each(fn youtube_id ->
        from(s in YtSearch.Thumbnail,
          update: [set: [keepalive: false]],
          where: s.id == ^youtube_id
        )
        |> ThumbnailRepo.update_all([])
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
            old_keepalived_slots
            |> Enum.map(fn slot ->
              %module{} = slot

              # to calculate if a given slot from A is in B we need to check
              # the video slot (and the channel slot the video slot refers to!)
              any_match? =
                data.search_results
                |> Enum.map(fn
                  %{
                    type: video_type,
                    slot_id: slot_id_str,
                    channel_slot: channel_slot_id
                  }
                  when video_type in [:video, :livestream, :short] and is_bitstring(slot_id_str) and
                         is_bitstring(channel_slot_id) ->
                    # either match on the video slot id, or match on the inner channel slot id
                    (module == YtSearch.Slot and slot_id_str == "#{slot.id}") or
                      (module == YtSearch.ChannelSlot and channel_slot_id == "#{slot.id}")

                  %{
                    type: video_type,
                    slot_id: slot_id_str,
                    channel_slot: nil
                  }
                  when video_type in [:video, :livestream, :short] and is_bitstring(slot_id_str) ->
                    # match on the video slot id
                    module == YtSearch.Slot and slot_id_str == "#{slot.id}"

                  # i forgot if playlists exist in the trending tab
                  %{type: :playlist, slot_id: slot_id_str, youtube_id: youtube_id}
                  when is_bitstring(slot_id_str) ->
                    module == YtSearch.PlaylistSlot and slot_id_str == "#{slot.id}" and
                      youtube_id == slot.youtube_id
                end)
                |> Enum.filter(fn match? -> match? end)
                |> Enum.at(0)
                |> then(fn
                  nil -> false
                  v -> v
                end)

              # if the old slot is not in the new refetched trending tab,
              # its safe to unset keepalive on the old slot

              if not any_match? do
                slot
                |> module.changeset(%{keepalive: false})
                |> SlotUtilities.repo(module).update()
              else
                {:ok, nil}
              end
            end)
            |> Enum.map(fn
              {:error, changeset} ->
                Logger.warning("failed to update, #{inspect(changeset)}")

              {:ok, _} ->
                :noop
            end)
          end

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
