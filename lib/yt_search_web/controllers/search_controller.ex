defmodule YtSearchWeb.SearchController do
  use YtSearchWeb, :controller

  require Logger
  alias YtSearch.SlotUtilities
  alias YtSearch.Youtube
  alias YtSearch.SearchSlot
  alias YtSearch.ChannelSlot
  alias YtSearch.PlaylistSlot
  alias YtSearch.ThumbnailerClient
  alias YtSearchWeb.Playlist
  alias YtSearchWeb.UserAgent

  def search_by_text(conn, _params) do
    case UserAgent.on(conn) do
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
    accept_header =
      case Plug.Conn.get_req_header(conn, "accept") do
        [] -> nil
        [value | _] -> value
      end

    if accept_header == "image/*" do
      case YtSearch.Thumbnail.Atlas.assemble(id) do
        {:ok, mimetype, binary_data} ->
          conn
          |> put_resp_content_type(mimetype, nil)
          |> resp(200, binary_data)

        {:error, :unknown_search_slot} ->
          conn
          |> put_status(404)
          |> text("search slot not found")
      end
    else
      case UserAgent.on(conn) do
        :unity ->
          do_search_by_slot(conn, id)

        _ ->
          conn
          |> put_status(400)
          |> json(%{error: true, message: "only unity should request this route"})
      end
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

        # decode slots_json once here; pass it down so
        # fetched_slots_from_search and the later thumbnailer sync reuse it
        entries = SearchSlot.get_slots(data)

        child_slots =
          data
          |> SearchSlot.fetched_slots_from_search(
            follow_inner_channel: true,
            follow_nextpage: true,
            entries: entries
          )

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
              true

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
          # one UPDATE per slot module (usually gated down to none)
          # instead of one UPDATE per child slot
          child_slots
          |> Enum.reject(&is_nil/1)
          |> Enum.group_by(fn %module{} -> module end)
          |> Enum.each(fn {module, slots} ->
            SlotUtilities.refresh_expiration_bulk(module, slots)
          end)

          data
          |> SlotUtilities.refresh_expiration()

          {data, entries}
        else
          nil
        end
    end
  end

  def broadcast_sync(search_slot, nextpage_search_slot \\ nil, opts \\ []) do
    search_sync_status = ThumbnailerClient.submit_search_slot(search_slot, opts)

    # the nextpage slot has its own slots_json, so it must NOT reuse the main
    # slot's decoded entries. it does keep any throttle flag so each slot
    # throttles on its own cache key.
    nextpage_sync_status =
      if nextpage_search_slot do
        ThumbnailerClient.submit_search_slot(
          nextpage_search_slot,
          Keyword.delete(opts, :entries)
        )
      else
        nil
      end

    search_sync_ok =
      case search_sync_status do
        :ok -> true
        _ -> false
      end

    nextpage_sync_ok =
      case nextpage_sync_status do
        :ok -> true
        nil -> nil
        _ -> false
      end

    {search_sync_ok, nextpage_sync_ok}
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

            # Sync to thumbnailer
            {search_sync_ok, nextpage_sync_ok} =
              broadcast_sync(search_slot, nextpage_search_slot)

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
                 end,
               search_sync_ok: search_sync_ok,
               nextpage_sync_ok: nextpage_sync_ok
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
        YtSearch.SearchSlot.validate_slot_type_fields!(unfetched_slot)

        with {:ok, %{results: _, nextpage: _} = ytdlp_data} <-
               Youtube.nextpage_fetch(unfetched_slot) do
          results =
            ytdlp_data
            |> Playlist.from_piped_data(nextpage?: true)

          {search_slot, nextpage_search_slot} =
            results
            |> SearchSlot.from_unfetched_slot(unfetched_slot)

          {search_sync_ok, nextpage_sync_ok} =
            broadcast_sync(search_slot, nextpage_search_slot)

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
               end,
             search_sync_ok: search_sync_ok,
             nextpage_sync_ok: nextpage_sync_ok
           }}
        end

      {%YtSearch.SearchSlot{} = search_slot, entries} ->
        nextpage_search_slot =
          if search_slot.nextpage_slot_id != nil,
            do: YtSearch.SearchSlot.fetch(search_slot.nextpage_slot_id),
            else: nil

        # cache hit: reuse the already-decoded entries for the main slot and
        # throttle the thumbnailer sync (both main + nextpage slots throttle on
        # their own keys). the nextpage slot is re-synced too: the thumbnailer's
        # copy may have expired even though ours is still valid.
        {search_sync_ok, nextpage_sync_ok} =
          broadcast_sync(search_slot, nextpage_search_slot, entries: entries, throttle: true)

        nextpage_search_slot_id = search_slot.nextpage_slot_id

        # cache hit: slots_json is already valid JSON, embed it raw
        # instead of decoding and re-encoding the largest response field
        search_results =
          case search_slot.type do
            :unfetched ->
              []

            _ when search_slot.slots_json != "" ->
              Jason.Fragment.new(search_slot.slots_json)

            _ ->
              search_slot |> SearchSlot.get_slots()
          end

        {:ok,
         %{
           result_type: search_slot.result_type,
           result_title: search_slot.result_title,
           search_results: search_results,
           slot_id: "#{search_slot.id}",
           nextpage_slot_id:
             if nextpage_search_slot_id != nil do
               "#{nextpage_search_slot_id}"
             else
               nil
             end,
           search_sync_ok: search_sync_ok,
           nextpage_sync_ok: nextpage_sync_ok
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
        # no broadcast_sync here: every success path of search/1 already
        # syncs the (re-resolved) search slot to the thumbnailer
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
