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
        conn
        |> put_status(404)
        |> assign(:slot, nil)
        |> render("slot.json")

      slot ->
        youtube_url = "https://youtube.com/watch?v=#{slot.youtube_id}"

        case UserAgent.for(conn) do
          :quest_video ->
            case Mp4Link.maybe_fetch_upstream(slot.youtube_id, youtube_url) do
              {:ok, nil} ->
                raise "should not happen"

              {:ok, link} ->
                case link |> Mp4Link.meta() |> Map.get("age_limit") do
                  0 ->
                    conn
                    |> redirect(external: link.mp4_link)

                  age_limit ->
                    Logger.warn("age restricted video. #{age_limit}")

                    conn
                    |> put_status(404)
                    |> text("age restricted video (#{age_limit})")
                end

              {:error, :video_unavailable} ->
                conn
                |> put_status(404)
                |> text("video unavailable")
            end

          :unity ->
            do_slot_metadata(conn, slot, youtube_url)

          _ ->
            conn
            |> redirect(external: youtube_url)
        end
    end
  end

  defp do_slot_metadata(conn, slot, youtube_url) do
    # for now, just find subtitles, but this can return future metadata
    subtitle_data = do_subtitles(slot, youtube_url)

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

  defp do_subtitles(slot, youtube_url, recursing \\ false) do
    # 1. fetch once, to see if we dont need to acquire the mutex
    # 2. fetch again inside the mutex, in the case another process was
    # already fetching the subtitles
    # 3. fetch after requesting a fetch, for the process that did the
    # hard job of calling youtube
    case subtitles_for(slot) do
      :no_requested_subtitles ->
        Mutex.under(SubtitleMutex, youtube_url, fn ->
          case subtitles_for(slot) do
            :no_requested_subtitles ->
              if recursing do
                Logger.warn("should not recurse twice into requesting subtitles")
                nil
              else
                Youtube.fetch_subtitles(youtube_url)
                do_subtitles(slot, youtube_url, true)
              end

            :no_available_subtitles ->
              nil

            data ->
              data
          end
        end)

      :no_available_subtitles ->
        nil

      data ->
        data
    end
  end
end
