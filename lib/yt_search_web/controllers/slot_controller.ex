defmodule YtSearchWeb.SlotController do
  use YtSearchWeb, :controller
  require Logger
  alias YtSearch.SlotUtilities
  alias YtSearch.Slot
  alias YtSearch.Mp4Link
  alias YtSearch.Subtitle
  alias YtSearch.Chapters
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
        conn
        |> redirect(external: slot |> Slot.youtube_url())
    end
  end

  def parse_slot_id(slot_id) do
    case slot_id |> Integer.parse() do
      {slot_id_int, ""} -> {:ok, slot_id_int}
      _ -> {:error, :invalid_slot_id}
    end
  end

  defp conn_has_invalid_slot(conn) do
    conn
    |> put_status(404)
    |> assign(:slot, nil)
    |> render("slot.json")
  end

  defp fetch_slot(slot_id) do
    case Slot.fetch_by_id(slot_id) do
      nil ->
        Logger.warning("unavailable to refresh (slot not found)")
        {:error, :slot_not_found}

      slot ->
        {:ok, slot}
    end
  end

  defp refresh_slot(slot) do
    if NaiveDateTime.diff(slot.used_at, NaiveDateTime.utc_now(), :second) <=
         -SlotUtilities.min_time_between_refreshes() do
      slot
      |> Slot.refresh()
    end

    :ok
  end

  def refresh(conn, %{"slot_id" => slot_id_query}) do
    with {:ok, slot_id} <- parse_slot_id(slot_id_query),
         {:ok, slot} <- fetch_slot(slot_id),
         :ok <- refresh_slot(slot) do
      conn
      |> put_status(200)
      |> json(%{})
    else
      {:error, :invalid_slot_id} ->
        conn_has_invalid_slot(conn)

      {:error, :slot_not_found} ->
        conn_has_invalid_slot(conn)
    end
  end

  # same as angel of death's reply
  @image_reply Path.join(:code.priv_dir(:yt_search), "static/retry.png")

  def refresh_with_image_reply(conn, %{"slot_id" => slot_id_query}) do
    with {:ok, slot_id} <- parse_slot_id(slot_id_query),
         {:ok, slot} <- fetch_slot(slot_id),
         :ok <- refresh_slot(slot) do
      conn
      |> put_resp_header("content-type", "image/png")
      |> resp(200, File.read!(@image_reply))
    else
      {:error, :invalid_slot_id} ->
        conn_has_invalid_slot(conn)

      {:error, :slot_not_found} ->
        conn_has_invalid_slot(conn)
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

    if conn.assigns[:want_stream] do
      # we can't redirect to a video when the quest player is in stream mode
      # so... 404 it
      conn
      |> put_status(404)
      |> text("error happened: #{error_code}")
    else
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
    googlevideo? = Application.get_env(:yt_search, YtSearch.Constants)[:redirect_to_googlevideo?]

    if googlevideo? do
      case Mp4Link.maybe_fetch_upstream(slot) do
        {:ok, link} ->
          redirect_to(conn, link)

        {:error, %Mp4Link{} = link} ->
          redirect_to(conn, link)

        {:error, _} = error ->
          Logger.error("failed to fetch upstream: #{inspect(error)}")
          redirect_to(conn, nil)
      end
    else
      conn
      |> redirect(external: slot |> Slot.youtube_url())
    end
  end

  def fetch_redirect(conn, %{"slot_id" => slot_id_query}) do
    {slot_id, _} = slot_id_query |> Integer.parse()

    case Slot.fetch_by_id(slot_id) do
      nil ->
        Logger.warning("unavailable (not found)")
        redirect_to(conn, nil)

      slot ->
        case UserAgent.for(conn) do
          :unity ->
            do_slot_metadata(conn, slot)

          _ ->
            case YtSearch.Slot.type(slot) do
              :video ->
                handle_quest_video(conn, slot)

              :livestream ->
                conn
                |> redirect(external: slot |> Slot.youtube_url())
            end
        end
    end
  end

  def fetch_stream_redirect(conn, args) do
    conn
    |> assign(:want_stream, true)
    |> fetch_redirect(args)
  end

  defp do_slot_metadata(conn, slot) do
    if NaiveDateTime.diff(slot.used_at, NaiveDateTime.utc_now(), :second) <=
         -SlotUtilities.min_time_between_refreshes() do
      slot
      |> Slot.refresh()
    end

    subtitle_task =
      Task.Supervisor.async_nolink(YtSearch.SlotMetadataSupervisor, fn ->
        do_subtitles(slot)
      end)

    sponsorblock_task =
      Task.Supervisor.async_nolink(YtSearch.SlotMetadataSupervisor, fn ->
        do_sponsorblock(slot) |> Jason.decode!()
      end)

    chapters_task =
      Task.Supervisor.async_nolink(YtSearch.SlotMetadataSupervisor, fn ->
        do_chapters(slot) |> Jason.decode!()
      end)

    subtitle_data = maybe_await(subtitle_task)
    sponsorblock_data = maybe_await(sponsorblock_task)
    chapters_data = maybe_await(chapters_task)

    conn
    |> json(%{
      duration: slot.video_duration,
      subtitle_data: subtitle_data,
      sponsorblock_segments: sponsorblock_data,
      chapters: chapters_data
    })
  end

  defp maybe_await(task, timeout \\ 5000) do
    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, result} ->
        result

      {:exit, reason} ->
        Logger.warning("task #{inspect(task)} failed with error: #{inspect(reason)}")
        nil

      nil ->
        Logger.warning("task #{inspect(task)} timeouted after #{timeout}ms")
        nil
    end
  end

  defp valid_subtitle_from_list(subtitles) do
    real_subtitles =
      subtitles
      |> Enum.filter(fn sub ->
        sub.language != "notfound"
      end)

    original? =
      real_subtitles
      |> Enum.find(fn subtitle ->
        String.ends_with?(subtitle.language, "-orig")
      end)

    if original? != nil do
      original?
    else
      real_subtitles |> Enum.at(0)
    end
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

  defp do_subtitles(slot, recursing \\ false) do
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

            if recursing do
              Logger.warning("already retried once, fast-failing!")
              nil
            else
              do_subtitles(slot, true)
            end
        end

      :no_subtitles_found ->
        nil

      data ->
        data
    end
  end

  alias YtSearch.Sponsorblock.Segments

  defp do_sponsorblock(slot) do
    case Segments.fetch(slot.youtube_id) do
      nil ->
        with {:ok, segments_data} <-
               YtSearch.MetadataExtractor.Worker.sponsorblock_segments(slot.youtube_id) do
          segments_data.segments_json
        end

      %Segments{} = segments ->
        segments.segments_json
    end
  end

  defp do_chapters(slot) do
    case Chapters.fetch(slot.youtube_id) do
      nil ->
        with {:ok, chapters} <-
               YtSearch.MetadataExtractor.Worker.chapters(slot.youtube_id) do
          chapters.chapter_data
        end

      %Chapters{} = chapters ->
        chapters.chapter_data
    end
  end
end
