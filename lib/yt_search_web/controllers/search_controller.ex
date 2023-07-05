defmodule YtSearchWeb.SearchController do
  use YtSearchWeb, :controller

  alias YtSearch.Youtube
  alias YtSearch.SearchSlot
  alias YtSearch.ChannelSlot
  alias YtSearch.PlaylistSlot
  alias YtSearchWeb.Playlist

  def search_by_text(conn, _params) do
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

  def search_from_any_youtube_url(youtube_url, conn) do
    {:ok, ytdlp_data} =
      youtube_url
      # channel_search works for playlists
      # as well because both are just "from this url give more stuff"
      # (which is also kind of how normal text search goes too...)
      # (TODO put all search cli calls into single pipeline)
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

  @spec fetch_youtube_entity(Plug.Conn.t(), atom(), String.t()) :: nil
  defp fetch_youtube_entity(conn, entity, id) do
    {slot_id, _} = id |> Integer.parse()

    case entity.fetch(slot_id) do
      nil ->
        conn
        |> put_status(404)

      slot ->
        slot
        |> entity.as_youtube_url()
        |> search_from_any_youtube_url(conn)
    end
  end

  def fetch_channel(conn, %{"channel_slot_id" => slot_id_query}) do
    fetch_youtube_entity(conn, ChannelSlot, slot_id_query)
  end

  def fetch_playlist(conn, %{"playlist_slot_id" => slot_id_query}) do
    fetch_youtube_entity(conn, PlaylistSlot, slot_id_query)
  end
end
