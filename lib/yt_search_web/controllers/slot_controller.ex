defmodule YtSearchWeb.SlotController do
  use YtSearchWeb, :controller
  alias YtSearch.Slot
  alias YtSearch.Mp4Link
  alias YtSearch.Youtube
  alias YtSearchWeb.UserAgent

  def fetch_video(conn, %{"slot_id" => slot_id_query}) do
    {slot_id, _} = slot_id_query |> Integer.parse()

    case Slot.fetch_by_id(slot_id) do
      nil ->
        conn
        |> put_status(404)

      slot ->
        youtube_url = "https://youtube.com/watch?v=#{slot.youtube_id}"

        case UserAgent.for(conn) do
          :quest ->
            {:ok, mp4_url} = Mp4Link.maybe_fetch_upstream(slot.youtube_id, youtube_url)

            conn
            |> redirect(external: mp4_url)

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
    subtitles_directory = "/tmp/yts-subtitles/#{slot.youtube_id}"

    result =
      Path.wildcard(subtitles_directory <> "/*#{slot.youtube_id}*en*.vtt")
      |> Enum.map(fn child_path ->
        {child_path, File.read(child_path)}
      end)
      |> Enum.filter(fn {path, result} ->
        case result do
          {:ok, data} ->
            true

          _ ->
            Logger.error("expected #{path} to work, got #{inspect(result)}")
            false
        end
      end)
      |> Enum.at(0)

    case result do
      nil -> nil
      {path, {:ok, data}} -> data
    end
  end

  defp do_subtitles(slot, youtube_url) do
    # 1. fetch once, to see if we dont need to acquire the mutex
    # 2. fetch again inside the mutex, in the case another process was
    # already fetching the subtitles
    # 3. fetch after requesting a fetch, for the process that did the
    # hard job of calling youtube
    case subtitles_for(slot) do
      nil ->
        Mutex.under(SubtitleMutex, youtube_url, fn ->
          case subtitles_for(slot) do
            nil ->
              :ok = Youtube.fetch_subtitles(youtube_url)
              # it should not be nil here
              case subtitles_for(slot) do
                nil ->
                  raise "subtitles must be available after fetching"

                v ->
                  v
              end

            data ->
              data
          end
        end)

      data ->
        data
    end
  end
end
