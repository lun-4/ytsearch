defmodule YtSearchWeb.SlotController do
  use YtSearchWeb, :controller
  require Logger
  alias YtSearch.Slot
  alias YtSearch.Mp4Link
  alias YtSearch.Subtitle
  alias YtSearch.Youtube
  alias YtSearchWeb.UserAgent

  def fetch_video(conn, %{"slot_id" => slot_id_query}) do
    {slot_id, _} = slot_id_query |> Integer.parse()

    case Slot.fetch_by_id(slot_id) do
      nil ->
        Logger.warning("unavailable (slot not found)")

        conn
        |> put_status(404)
        |> assign(:slot, nil)
        |> render("slot.json")

      slot ->
        case UserAgent.for(conn) do
          :quest_video ->
            handle_quest_video(conn, slot)

          :unity ->
            do_slot_metadata(conn, slot)

          _ ->
            conn
            |> redirect(external: slot |> Slot.youtube_url())
        end
    end
  end

  defp handle_quest_video(conn, slot) do
    case Mp4Link.maybe_fetch_upstream(slot) do
      {:ok, nil} ->
        raise "should not happen"

      {:ok, link} ->
        conn
        |> redirect(external: link.mp4_link)

      {:error, :video_unavailable} ->
        Logger.warning("unavailable (video unavailable)")

        conn
        |> put_status(404)
        |> text("video unavailable")

      {:error, :upcoming_video} ->
        Logger.warning("unavailable (upcoming video)")

        conn
        |> put_status(404)
        |> text("video unavailable (upcoming video)")
    end
  end

  def fetch_redirect(conn, %{"slot_id" => slot_id_query}) do
    {slot_id, _} = slot_id_query |> Integer.parse()

    case Slot.fetch_by_id(slot_id) do
      nil ->
        Logger.warning("unavailable (not found)")

        conn
        |> put_status(404)
        |> assign(:slot, nil)
        |> render("slot.json")

      slot ->
        handle_quest_video(conn, slot)
    end
  end

  defp do_slot_metadata(conn, slot) do
    # for now, just find subtitles, but this can return future metadata
    subtitle_data = do_subtitles(slot)

    conn
    |> json(%{subtitle_data: subtitle_data})
  end

  defp subtitles_for(slot) do
    subtitles = Subtitle.fetch(slot.youtube_id)

    if length(subtitles) == 0 do
      :no_requested_subtitles
    else
      selected =
        subtitles
        |> Enum.filter(fn sub ->
          sub.language != "notfound"
        end)
        |> Enum.at(0)

      case selected do
        nil -> :no_subtitles_found
        subtitle -> subtitle.subtitle_data
      end
    end
  end

  defp do_subtitles(slot, recursing \\ false) do
    # 1. fetch once, to see if we dont need to acquire the mutex
    # 2. fetch again inside the mutex, in the case another process was
    # already fetching the subtitles
    # 3. fetch after requesting a fetch, for the process that did the
    # hard job of calling youtube

    case subtitles_for(slot) do
      :no_requested_subtitles ->
        if recursing do
          Logger.warning("should not recurse twice into requesting subtitles")
          nil
        else
          YtSearch.MetadataExtractor.Worker.subtitles(slot.youtube_id)
          do_subtitles(slot, true)
        end

      :no_available_subtitles ->
        nil

      :no_subtitles_found ->
        nil

      data ->
        data
    end
  end
end
