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

    case search_text(escaped_query) do
      {:ok, response} ->
        conn
        |> put_status(200)
        |> json(response)

      {:error, :overloaded_ytdlp_seats} ->
        conn
        |> put_status(429)
        |> json(%{error: true, detail: "server overloaded"})
    end
  end

  defp fetch_by_query_and_valid(url) do
    case SearchSlot.fetch_by_query(url) do
      nil ->
        nil

      data ->
        # we want to have a search slot that contains valid slots within
        valid_slots =
          data
          |> SearchSlot.fetched_slots_from_search()
          |> Enum.map(fn maybe_slot ->
            maybe_slot != nil
          end)

        is_valid_slot =
          unless length(valid_slots) == 0 do
            valid_slots
            |> Enum.reduce(fn x, acc ->
              x and acc
            end)
          else
            false
          end

        if is_valid_slot do
          data
        else
          nil
        end
    end
  end

  # TODO remove duplicates

  def search_text(text) do
    case fetch_by_query_and_valid(text) do
      nil ->
        case Youtube.videos_for(text) do
          {:ok, ytdlp_data} ->
            results =
              ytdlp_data
              |> Playlist.from_piped_data()

            search_slot =
              results
              |> SearchSlot.from_playlist(text)

            {:ok, %{search_results: results, slot_id: "#{search_slot.id}"}}

          {:error, :overloaded_ytdlp_seats} ->
            {:error, :overloaded_ytdlp_seats}
        end

      search_slot ->
        {:ok,
         %{search_results: search_slot |> SearchSlot.get_slots(), slot_id: "#{search_slot.id}"}}
    end
  end

  @spec fetch_youtube_entity(Plug.Conn.t(), atom(), String.t()) :: nil
  defp fetch_youtube_entity(conn, entity, id) do
    {slot_id, _} = id |> Integer.parse()

    case entity.fetch(slot_id) do
      nil ->
        conn
        |> put_status(404)
        |> text("not found")

      slot ->
        {:ok, resp} =
          slot
          |> search_text()

        conn
        |> put_status(200)
        |> json(resp)
    end
  end

  def fetch_channel(conn, %{"channel_slot_id" => slot_id_query}) do
    fetch_youtube_entity(conn, ChannelSlot, slot_id_query)
  end

  def fetch_playlist(conn, %{"playlist_slot_id" => slot_id_query}) do
    fetch_youtube_entity(conn, PlaylistSlot, slot_id_query)
  end
end
