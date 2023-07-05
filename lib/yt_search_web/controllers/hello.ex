defmodule YtSearchWeb.HelloController do
  use YtSearchWeb, :controller

  alias YtSearch.Youtube
  alias YtSearch.SearchSlot
  alias YtSearchWeb.Playlist

  def hello(conn, _params) do
    # TODO cache this
    trending_tab =
      "https://www.youtube.com/feed/trending"
      |> YtSearchWeb.SearchController.search_from_any_youtube_url()

    conn
    |> json(%{online: true, trending_tab: trending_tab})
  end
end
