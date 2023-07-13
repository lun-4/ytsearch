defmodule YtSearchWeb.SearchController do
  use YtSearchWeb, :controller

  alias YtSearch.Youtube
  alias YtSearch.SearchSlot
  alias YtSearch.ChannelSlot
  alias YtSearch.PlaylistSlot
  alias YtSearchWeb.Playlist
  alias YtSearchWeb.UserAgent

  def search_by_text(conn, _params) do
    case UserAgent.for(conn) do
      :unity ->
        case conn.query_params["search"] || conn.query_params["q"] do
          nil ->
            conn
            |> put_status(400)
            |> json(%{error: true, message: "need search param fam"})

          search_query ->
            do_search(conn, search_query)
        end

      _ ->
        # if search is given to a video player in vrchat, you now have a
        # morbillion players requesting the same search route.

        # that's an invalid use of the world and the api.
        conn
        |> put_status(400)
        |> json(%{error: true, message: "only unity should request this route"})
    end
  end

  @type entity_type :: :channel | :short | :video

  def do_search(conn, search_query) do
    escaped_query =
      search_query
      |> String.trim()
      |> URI.encode()

    "https://www.youtube.com/results?search_query=#{escaped_query}"
    |> search_from_any_youtube_url(conn)
  end

  def search_from_any_youtube_url(youtube_url, playlist_end \\ 20)
      when is_integer(playlist_end) do
    case youtube_url |> Youtube.search_from_url(playlist_end) do
      {:ok, ytdlp_data} ->
        results =
          ytdlp_data
          |> Playlist.from_ytdlp_data()

        search_slot =
          results
          |> SearchSlot.from_playlist()

        {:ok, %{search_results: results, slot_id: "#{search_slot.id}"}}

      {:error, :overloaded_ytdlp_seats} ->
        {:error, :overloaded_ytdlp_seats}
    end
  end

  def search_from_any_youtube_url(youtube_url, conn) do
    case search_from_any_youtube_url(youtube_url) do
      {:ok, jsondata} ->
        conn
        |> json(jsondata)

      {:error, :overloaded_ytdlp_seats} ->
        conn
        |> put_status(429)
        |> json(%{error: true, detail: "server overloaded"})
    end
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
