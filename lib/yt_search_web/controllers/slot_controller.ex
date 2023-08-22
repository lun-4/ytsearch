defmodule YtSearchWeb.SlotController do
  use YtSearchWeb, :controller
  require Logger
  alias YtSearch.Slot
  alias YtSearch.Mp4Link
  alias YtSearch.Subtitle
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

  @error_video_directory Path.join(:code.priv_dir(:yt_search), "static/redirect_errors")

  defp show_error_video(conn, error_code) do
    conn =
      conn
      |> put_resp_header("yts-failure-code", error_code)

    # let ops override error videos so actual file sending is offloaded
    external_url =
      case System.fetch_env("YTS_ERROR_VIDEO_URL_#{error_code}") do
        :error -> nil
        {:ok, ""} -> nil
        {:ok, url} -> url
      end

    unless conn.assigns[:want_stream] do
      if external_url == nil do
        conn
        |> put_resp_content_type("video/mp4", nil)
        |> send_file(
          200,
          Path.join(
            @error_video_directory,
            "yts_error_message_#{error_code |> String.downcase()}.mp4"
          )
        )
      else
        conn
        |> redirect(external: external_url)
      end
    else
      # we can't redirect to a video when the quest player is in stream mode
      # so... 404 it
      conn
      |> put_status(404)
      |> text("error happened: #{error_code}")
    end
  end

  defp redirect_to(conn, link) do
    cond do
      link == nil ->
        # redirect to E00
        show_error_video(conn, "E00")

      link.mp4_link == nil ->
        show_error_video(conn, link.error_reason)

      true ->
        conn
        |> redirect(external: link.mp4_link)
    end
  end

  defp handle_quest_video(conn, slot) do
    case Mp4Link.maybe_fetch_upstream(slot) do
      {:ok, nil} ->
        raise "should not happen"

      {:ok, link} ->
        redirect_to(conn, link)

      {:error, %Mp4Link{} = link} ->
        redirect_to(conn, link)
    end
  end

  def fetch_redirect(conn, %{"slot_id" => slot_id_query}) do
    {slot_id, _} = slot_id_query |> Integer.parse()

    case Slot.fetch_by_id(slot_id) do
      nil ->
        Logger.warning("unavailable (not found)")
        redirect_to(conn, nil)

      slot ->
        handle_quest_video(conn, slot)
    end
  end

  def fetch_stream_redirect(conn, args) do
    conn
    |> assign(:want_stream, true)
    |> fetch_redirect(args)
  end

  defp do_slot_metadata(conn, slot) do
    # for now, just find subtitles, but this can return future metadata
    subtitle_data = do_subtitles(slot)

    conn
    |> json(%{subtitle_data: subtitle_data})
  end

  defp valid_subtitle_from_list(subtitles) do
    subtitles
    |> Enum.filter(fn sub ->
      sub.language != "notfound"
    end)
    |> Enum.at(0)
  end

  defp subtitles_for(slot) do
    subtitles = Subtitle.fetch(slot.youtube_id)

    if Enum.empty?(subtitles) do
      :no_requested_subtitles
    else
      case valid_subtitle_from_list(subtitles) do
        nil -> :no_subtitles_found
        subtitle -> subtitle.subtitle_data
      end
    end
  end

  defp do_subtitles(slot) do
    # 1. fetch once, to see if we dont need to acquire the mutex
    # 2. fetch again inside the mutex, in the case another process was
    # already fetching the subtitles
    # 3. fetch after requesting a fetch, for the process that did the
    # hard job of calling youtube

    case subtitles_for(slot) do
      :no_requested_subtitles ->
        case YtSearch.MetadataExtractor.Worker.subtitles(slot.youtube_id) do
          {:ok, subtitles} ->
            subtitles
            |> valid_subtitle_from_list()
            |> then(fn maybe_subtitle ->
              if maybe_subtitle == nil do
                nil
              else
                maybe_subtitle.subtitle_data
              end
            end)

          value ->
            Logger.warning("expected subtitles, got #{inspect(value)}, retrying...")
            do_subtitles(slot)
        end

      :no_subtitles_found ->
        nil

      data ->
        data
    end
  end
end
