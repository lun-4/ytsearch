defmodule YtSearchWeb.HelloController do
  use YtSearchWeb, :controller
  require Logger

  def hello(conn, _params) do
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

  defp do_fetch_trending_tab() do
    url = "https://www.youtube.com/feed/trending"

    Mutex.under(SearchMutex, url, fn ->
      case Cachex.get(:tabs, "trending") do
        {:ok, nil} ->
          data =
            url
            |> YtSearchWeb.SearchController.search_from_any_youtube_url()

          Cachex.put(
            :tabs,
            "trending",
            case data do
              nil -> :nothing
              v -> v
            end,
            ttl: 2 * 3600 * 1000
          )

          {:ok, data}

        v ->
          v
      end
    end)
  end
end
