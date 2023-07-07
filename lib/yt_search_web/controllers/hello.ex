defmodule YtSearchWeb.HelloController do
  use YtSearchWeb, :controller

  alias YtSearch.Youtube
  alias YtSearch.SearchSlot
  alias YtSearchWeb.Playlist

  def hello(conn, _params) do
    trending_tab =
      case Cachex.get(:tabs, "trending") do
        {:ok, nil} ->
          data =
            "https://www.youtube.com/feed/trending"
            |> YtSearchWeb.SearchController.search_from_any_youtube_url()

          Cachex.set(
            :tabs,
            "trending",
            case data do
              nil -> :nothing
              v -> v
            end,
            ttl: 2 * 3600 * 1000
          )

          data

        {:ok, :nothing} ->
          nil

        {:ok, data} ->
          data

        value ->
          Logger.error("trending tab fetch failed: #{inspect(value)}")
          nil
      end

    conn
    |> json(%{online: true, trending_tab: trending_tab})
  end
end
