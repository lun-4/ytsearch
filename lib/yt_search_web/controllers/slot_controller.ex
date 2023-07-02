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
            mp4_url = Mp4Link.maybe_fetch_upstream(slot.youtube_id, youtube_url)

            conn
            |> redirect(external: mp4_url)

          :unity ->
            # for now, just find subtitles, but this can return future metadata
            {:ok, subtitle_data} = Youtube.fetch_subtitles(youtube_url)

            conn
            |> json(%{subtitle_data: subtitle_data})

          _ ->
            conn
            |> redirect(external: youtube_url)
        end
    end
  end
end
