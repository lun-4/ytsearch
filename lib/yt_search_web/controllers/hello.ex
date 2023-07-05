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
    {:ok, ytdlp_data} =
      "https://www.youtube.com/feed/trending"
      |> Youtube.channel_search()

    results =
      ytdlp_data
      |> Playlist.from_ytdlp_data()

    search_slot =
      results
      |> SearchSlot.from_playlist()

    conn
    |> json(%{search_results: results, slot_id: "#{search_slot.id}"})
  end
end
