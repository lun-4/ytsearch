defmodule YtSearchWeb.SearchController do
  use YtSearchWeb, :controller

  alias YtSearch.Youtube
  alias YtSearch.SearchSlot
  alias YtSearchWeb.Playlist

  def search(conn, _params) do
    case conn.query_params["search"] || conn.query_params["q"] do
      nil ->
        conn
        |> put_status(400)
        |> json(%{error: true, message: "need search param fam"})

      search_query ->
        do_search(conn, search_query)
    end
  end

  @type entity_type :: :channel | :short | :video

  def do_search(conn, search_query) do
    {:ok, youtube_json_results} = Youtube.search(search_query)

    results = youtube_json_results |> Playlist.from_ytdlp_data()
    search_slot = SearchSlot.from_playlist(results)

    conn
    |> json(%{
      search_results: results,
      slot_id: "#{search_slot.id}"
    })
  end
end
