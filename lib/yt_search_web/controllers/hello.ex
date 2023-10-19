defmodule YtSearchWeb.HelloController do
  use YtSearchWeb, :controller
  require Logger
  alias YtSearch.SearchSlot
  alias YtSearch.Youtube
  alias YtSearch.Repo
  alias YtSearchWeb.Playlist

  def hello(conn, params) do
    __MODULE__.BuildReporter.increment(params["build_number"] || "<unknown>")
    trending_tab = fetch_trending_tab()

    conn
    |> json(%{online: true, trending_tab: trending_tab})
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
      |> Repo.all()
    end)
    |> List.flatten()
  end

  defp upstream_trending_tab do
    {:ok, data} = Youtube.trending()

    # TODO do keepalive dance for trending tab
    results =
      data
      |> Playlist.from_piped_data(keepalive: true)

    search_slot =
      results
      |> SearchSlot.from_playlist("yt://trending", keepalive: true)

    {:ok, %{search_results: results, slot_id: "#{search_slot.id}"}}
  end

  defp unkeepalive_thumbnails() do
    # thumbnails follow different logic from slots, unkeepalive them prematurely
    # (slots are more important to keep alive mid-trending-tab-refresh than thumbs)

    from(s in YtSearch.Thumbnail, update: [set: [keepalive: false]], where: s.keepalive)
    |> Repo.update_all([])
  end

  defp do_fetch_trending_tab() do
    url = "https://www.youtube.com/feed/trending"

    Mutex.under(SearchMutex, url, fn ->
      case Cachex.get(:tabs, "trending") do
        {:ok, nil} ->
          unkeepalive_thumbnails()
          old_keepalived_slots = keepalived_slots()
          {:ok, data} = upstream_trending_tab()

          Cachex.put(
            :tabs,
            "trending",
            case data do
              nil -> :nothing
              v -> v
            end,
            # 2 hours
            ttl: 2 * 60 * 60 * 1000
          )

          old_keepalived_slots
          |> Enum.map(fn slot ->
            %module{} = slot

            any_match? =
              data.search_results
              |> Enum.map(fn
                %{type: :channel, slot_id: slot_id_str} ->
                  module == YtSearch.ChannelSlot and slot_id_str == "#{slot.id}"

                %{type: video_type, slot_id: slot_id_str}
                when video_type in [:video, :livestream, :short] ->
                  module == YtSearch.Slot and slot_id_str == "#{slot.id}"

                %{type: :playlist, slot_id: slot_id_str} ->
                  module == YtSearch.PlaylistSlot and slot_id_str == "#{slot.id}"
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
              |> Ecto.Changeset.change(%{keepalive: false})
              |> Repo.update()
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
