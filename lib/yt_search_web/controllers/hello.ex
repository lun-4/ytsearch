defmodule YtSearchWeb.HelloController do
  use YtSearchWeb, :controller
  require Logger
  alias YtSearch.Slot
  alias YtSearch.SearchSlot
  alias YtSearch.Youtube
  alias YtSearch.Thumbnail
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

  defp upstream_trending_tab do
    {:ok, data} = Youtube.trending()

    # TODO do keepalive dance for trending tab
    results =
      data
      |> Playlist.from_piped_data()

    search_slot =
      results
      |> SearchSlot.from_playlist("yt://trending")

    {:ok, %{search_results: results, slot_id: "#{search_slot.id}"}}
  end

  defp do_fetch_trending_tab() do
    url = "https://www.youtube.com/feed/trending"

    Mutex.under(SearchMutex, url, fn ->
      case Cachex.get(:tabs, "trending") do
        {:ok, nil} ->
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

          {:ok, data}

        v ->
          v
      end
    end)
  end

  defmodule Refresher do
    alias YtSearch.PlaylistSlot
    alias YtSearch.ChannelSlot
    require Logger

    def tick() do
      Logger.info("refreshing trending tab slots...")

      case Cachex.get(:tabs, "trending") do
        {:ok, nil} ->
          nil

        {:ok, :nothing} ->
          nil

        {:ok, data} ->
          data[:slot_id]
          |> SearchSlot.refresh()

          case data[:search_results] do
            nil ->
              nil

            results ->
              results
              |> Enum.each(fn search_result ->
                slot_id = search_result[:slot_id]

                channel_slot = search_result[:channel_slot]

                unless channel_slot == nil do
                  channel_slot
                  |> Integer.parse()
                  |> then(fn {result, ""} -> result end)
                  |> ChannelSlot.refresh()
                end

                slot =
                  case search_result[:type] do
                    t when t in [:video, :short, :livestream] ->
                      Slot.refresh(slot_id)

                    :channel ->
                      ChannelSlot.refresh(slot_id)

                    :livestream ->
                      PlaylistSlot.refresh(slot_id)

                    _ ->
                      nil
                  end

                unless slot == nil do
                  Thumbnail.refresh(slot.youtube_id)
                end
              end)
          end
      end

      Logger.info("trending tab refresher complete")
    end
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
