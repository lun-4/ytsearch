defmodule YtSearchWeb.SearchController do
  use YtSearchWeb, :controller

  require Logger
  alias YtSearch.SlotUtilities
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

  def search_by_id(conn, %{"id" => id}) do
    case UserAgent.for(conn) do
      :unity ->
        do_search_by_slot(conn, id)

      _ ->
        conn
        |> put_status(400)
        |> json(%{error: true, message: "only unity should request this route"})
    end
  end

  def do_search(conn, search_query) do
    escaped_query =
      search_query
      |> String.trim()

    case search(escaped_query) do
      {:ok, response} ->
        conn
        |> put_status(200)
        |> json(response)

      {:error, :overloaded_ytdlp_seats} ->
        conn
        |> put_status(429)
        |> json(%{error: true, detail: "server overloaded"})

      {:error, :video_unavailable} ->
        conn
        |> put_status(404)
        |> json(%{error: false, detail: "video not found"})

      {:input_error, err} ->
        Logger.warning("input error when searching '#{escaped_query}': #{inspect(err)}")

        conn
        |> put_status(200)
        |> json(%{search_results: []})
    end
  end

  def do_search_by_slot(conn, id) do
    fetch_youtube_entity(conn, YtSearch.SearchSlot, id)
  end

  defp fetch_by_query_and_valid(url) do
    maybe_playlist_id =
      case Youtube.parse_url(url) do
        {:playlist, playlist_id} -> playlist_id
        _ -> nil
      end

    case SearchSlot.fetch_by_query(url) do
      nil ->
        nil

      %{type: :unfetched} = data ->
        data

      data ->
        # we want to have a search slot that contains valid slots within
        # NOTE: asserts slots are "strict TTL" (aka they use TTL.maybe?/1)

        child_slots =
          data
          |> SearchSlot.fetched_slots_from_search(follow_inner_channel: true)

        valid_slots =
          child_slots
          |> Enum.map(fn maybe_slot ->
            maybe_slot != nil
          end)

        is_valid_slot =
          cond do
            maybe_playlist_id != nil ->
              false

            Enum.empty?(valid_slots) ->
              false

            true ->
              valid_slots
              |> Enum.reduce(fn x, acc ->
                x and acc
              end)
          end

        Logger.info("attempting to reuse search slot #{data.id}, is valid? #{is_valid_slot}")
        Logger.debug("valid_slots = #{inspect(valid_slots)}")
        Logger.debug("child_slots = #{inspect(child_slots)}")

        if is_valid_slot do
          child_slots
          |> Enum.reduce(%{}, fn slot, acc ->
            Logger.debug("attempt to refresh #{inspect(slot)}")

            %module{} = slot
            refreshed? = Map.get(acc, {module, slot.id})

            unless refreshed? do
              case slot do
                %YtSearch.Slot{} ->
                  YtSearch.Slot.refresh(slot)

                other_slot ->
                  other_slot
                  |> SlotUtilities.refresh_expiration()
              end
            end

            acc |> Map.put({module, slot.id}, true)
          end)

          data
          |> SlotUtilities.refresh_expiration()

          data
        else
          nil
        end
    end
  end

  def search(entity) do
    case fetch_by_query_and_valid(entity) do
      nil ->
        case Youtube.fetch(entity) do
          {:ok, %{results: _, nextpage: _} = ytdlp_data} ->
            results =
              ytdlp_data
              |> Playlist.from_piped_data(nextpage?: true)

            {search_slot, nextpage_search_slot} =
              results
              |> SearchSlot.from_playlist(entity, nextpage?: true)

            {:ok,
             %{
               result_type: search_slot.result_type,
               result_title: search_slot.result_title,
               search_results: results.results,
               slot_id: "#{search_slot.id}",
               nextpage_slot_id:
                 if nextpage_search_slot != nil do
                   "#{nextpage_search_slot.id}"
                 else
                   nil
                 end
             }}

          {:error, :overloaded_ytdlp_seats} ->
            {:error, :overloaded_ytdlp_seats}

          {:error, :video_unavailable} ->
            {:error, :video_unavailable}

          {:error, :channel_unavailable} ->
            {:error, :channel_unavailable}

          {:error, :channel_not_found} ->
            {:error, :channel_not_found}

          {:input_error, err} ->
            {:input_error, err}
        end

      %YtSearch.SearchSlot{type: :unfetched} = unfetched_slot ->
        with {:ok, %{results: _, nextpage: _} = ytdlp_data} <-
               Youtube.nextpage_fetch(unfetched_slot) do
          results =
            ytdlp_data
            |> Playlist.from_piped_data(nextpage?: true)

          {search_slot, nextpage_search_slot} =
            results
            |> SearchSlot.from_unfetched_slot(unfetched_slot)

          {:ok,
           %{
             result_type: search_slot.result_type,
             result_title: search_slot.result_title,
             search_results: results.results,
             slot_id: "#{search_slot.id}",
             nextpage_slot_id:
               if nextpage_search_slot != nil do
                 "#{nextpage_search_slot.id}"
               else
                 nil
               end
           }}
        end

      search_slot ->
        {:ok,
         %{
           result_type: search_slot.result_type,
           result_title: search_slot.result_title,
           search_results: search_slot |> SearchSlot.get_slots(),
           slot_id: "#{search_slot.id}",
           nextpage_slot_id: "#{search_slot.nextpage_slot_id}"
         }}
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
        case slot
             |> search() do
          {:ok, resp} ->
            slot |> SlotUtilities.mark_used()

            conn
            |> put_status(200)
            |> json(resp)

          {:error, :channel_not_found} ->
            conn
            |> put_status(404)
            |> json(%{error: true, detail: "channel not found"})

          {:error, :channel_unavailable} ->
            conn
            |> put_status(404)
            |> json(%{error: true, detail: "channel unavailable"})
        end
    end
  end

  def fetch_channel(conn, %{"channel_slot_id" => slot_id_query}) do
    fetch_youtube_entity(conn, ChannelSlot, slot_id_query)
  end

  def fetch_playlist(conn, %{"playlist_slot_id" => slot_id_query}) do
    fetch_youtube_entity(conn, PlaylistSlot, slot_id_query)
  end
end
