defmodule YtSearchWeb.HelloController do
  use YtSearchWeb, :controller

  alias YtSearch.Youtube
  alias YtSearch.SearchSlot
  alias YtSearchWeb.Playlist

  def hello(conn, _params) do
    conn
    |> json(%{online: true})
  end

  def trending_tab(conn, _params) do
    "https://www.youtube.com/feed/trending"
    |> YtSearchWeb.SearchController.search_from_any_youtube_url(conn)
  end
end
